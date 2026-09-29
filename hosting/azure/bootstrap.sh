#!/usr/bin/env bash
# Operator bring-up for the azure profile, pass by pass. Upstream-owned.
# Every pass is idempotent; rerun any of them at any time.
#
#   group       create the resource group
#   foundation  deploy + runtime identities, both Key Vaults, registry, network + public IP (no VM)
#   secrets     CI deploy SSH key pair and oauth2-proxy cookie secret (generated once),
#               OAuth client (from OAUTH_CLIENT_ID / OAUTH_CLIENT_SECRET when set)
#   vm          the VM and its data disk; needs the deploy public key from `secrets`
#   host-key    print the VM's SSH host key (the SSH_HOST_PUBLIC_KEY repository variable)
#   github      write the repository variables and create the `production` environment
#   outputs     print the values the other passes and the workflows use
#   all         group foundation secrets vm host-key github outputs
#
# Usage: hosting/azure/bootstrap.sh [pass] [--what-if] [--pipeline]
#
#   --what-if    Bicep what-if instead of apply (foundation, vm)
#   --pipeline   running as the GitHub deploy identity: no role assignments, no officer
#
# The instance comes from site/claw.env (CLAW_INSTANCE, CLAW_HOSTNAME); the environment wins.
#
# Environment:
#   AZURE_SUBSCRIPTION_ID   required
#   AZURE_RESOURCE_GROUP    default rg-<instance>
#   LOCATION                default westeurope (group pass only)
#   GITHUB_REPOSITORY       owner/name; default: `gh repo view` of this checkout
#   GITHUB_REPOSITORY_WITH_IDS  owner@id/name@id; default: derived (Actions env or `gh api`),
#                           set it empty to register only the plain OIDC subject
#   SSH_PUBLIC_KEYS         JSON array of operator SSH public keys (default [])
#   SSH_SOURCE_CIDRS        JSON array of operator CIDRs allowed on port 22 (default [])
#   OAUTH_CLIENT_ID / OAUTH_CLIENT_SECRET   secrets pass, optional
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

pass="all"
what_if=false
pipeline=false
for arg in "$@"; do
  case "$arg" in
    --what-if) what_if=true ;;
    --pipeline) pipeline=true ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    --*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) pass="$arg" ;;
  esac
done

# Resolve the site's values the same way every other command does: bin/claw
# (profile defaults, then site/claw.env, then the caller's environment).
site_value() { # <name>
  bin/claw env | sed -n "s/^$1=//p"
}

profile="$(site_value CLAW_PROFILE)"
[[ "$profile" == azure ]] || echo "warning: site/claw.env has CLAW_PROFILE=${profile:-<unset>}, not azure" >&2
instance="$(site_value CLAW_INSTANCE)"
[[ "$instance" =~ ^[a-z][a-z0-9-]{1,23}$ ]] \
  || { echo "CLAW_INSTANCE must be 2-24 chars of [a-z0-9-], got '${instance}'" >&2; exit 2; }
claw_hostname="$(site_value CLAW_HOSTNAME)"

: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
location="${LOCATION:-westeurope}"
rg="${AZURE_RESOURCE_GROUP:-rg-$instance}"
vm_name="vm-$instance"
ssh_public_keys="${SSH_PUBLIC_KEYS:-[]}"
ssh_source_cidrs="${SSH_SOURCE_CIDRS:-[]}"

az() { command az "$@" --subscription "$AZURE_SUBSCRIPTION_ID"; }
log() { printf '\n== %s\n' "$*"; }

# Temp files are removed explicitly at the end of each pass and by this EXIT trap on any
# abort. (A RETURN trap inside a function fires again when its caller returns, after the
# function's locals are gone — bash 3.2 on macOS.)
cleanup_paths=()
cleanup() { for path in ${cleanup_paths[@]+"${cleanup_paths[@]}"}; do rm -rf "$path"; done; }
trap cleanup EXIT

json_array_or_die() { # <name> <value>
  jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' <<<"$2" >/dev/null \
    || { echo "$1 must be a JSON array of non-empty strings, got: $2" >&2; exit 2; }
}
json_array_or_die SSH_PUBLIC_KEYS "$ssh_public_keys"
json_array_or_die SSH_SOURCE_CIDRS "$ssh_source_cidrs"

github_repository() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf '%s' "$GITHUB_REPOSITORY"
  else
    gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null \
      || { echo "Set GITHUB_REPOSITORY=owner/name (or run inside a gh-authenticated checkout)" >&2; exit 2; }
  fi
}

# The id-qualified OIDC subject form. Actions exports the ids; an operator asks the API.
github_repository_with_ids() { # <owner/name>
  if [[ -n "${GITHUB_REPOSITORY_WITH_IDS+set}" ]]; then
    printf '%s' "$GITHUB_REPOSITORY_WITH_IDS"
  elif [[ -n "${GITHUB_REPOSITORY_OWNER_ID:-}" && -n "${GITHUB_REPOSITORY_ID:-}" ]]; then
    printf '%s@%s/%s@%s' "${1%%/*}" "$GITHUB_REPOSITORY_OWNER_ID" "${1#*/}" "$GITHUB_REPOSITORY_ID"
  else
    gh api "repos/$1" --jq '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"' 2>/dev/null || true
  fi
}

# Object id of the signed-in operator, read from the ARM token so no Graph call is needed.
signed_in_object_id() {
  az account get-access-token --query accessToken -o tsv \
    | cut -d. -f2 | tr '_-' '/+' \
    | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' \
    | base64 -d 2>/dev/null | jq -r '.oid'
}

foundation_output() { # <name>
  az deployment group show -g "$rg" -n foundation --query "properties.outputs.$1.value" -o tsv
}

kv_secret_exists() { az keyvault secret show --vault-name "$1" --name "$2" -o none 2>/dev/null; }

deploy_template() { # <deployment-name> <deployVm>
  local deployment="$1" deploy_vm="$2" params repo repo_ids
  params="$(mktemp)"
  chmod 600 "$params"
  cleanup_paths+=("$params")
  repo="$(github_repository)"
  repo_ids="$(github_repository_with_ids "$repo")"

  local keys="$ssh_public_keys"
  if [[ "$deploy_vm" == true ]]; then
    local kv deploy_pub
    kv="$(foundation_output keyVaultName)"
    deploy_pub="$(az keyvault secret show --vault-name "$kv" --name ssh-deploy-public-key --query value -o tsv 2>/dev/null || true)"
    if [[ -z "$deploy_pub" ]]; then
      echo "Key Vault secret ssh-deploy-public-key is missing — run the secrets pass first." >&2
      exit 1
    fi
    keys="$(jq -c --arg k "$deploy_pub" '[$k] + .' <<<"$ssh_public_keys")"
  fi

  local deployer_id="" manage=true
  if [[ "$pipeline" == true ]]; then
    manage=false
  else
    deployer_id="$(signed_in_object_id)"
  fi

  jq -n \
    --arg instance "$instance" \
    --arg repo "$repo" \
    --arg repoIds "$repo_ids" \
    --arg deployer "$deployer_id" \
    --argjson manage "$manage" \
    --argjson deployVm "$deploy_vm" \
    --argjson keys "$keys" \
    --argjson cidrs "$ssh_source_cidrs" \
    '{
      "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
      contentVersion: "1.0.0.0",
      parameters: {
        instance: { value: $instance },
        githubRepository: { value: $repo },
        githubRepositoryWithIds: { value: $repoIds },
        deployerPrincipalId: { value: $deployer },
        manageRoleAssignments: { value: $manage },
        deployVm: { value: $deployVm },
        sshPublicKeys: { value: $keys },
        sshSourceCidrs: { value: $cidrs }
      }
    }' > "$params"

  local template=hosting/azure/infra/main.bicep
  if [[ "$what_if" == true ]]; then
    az deployment group what-if -g "$rg" -n "$deployment" --template-file "$template" --parameters @"$params"
  else
    az deployment group create -g "$rg" -n "$deployment" --template-file "$template" --parameters @"$params" -o none
  fi
  rm -f "$params"
}

pass_group() {
  log "resource group $rg ($location)"
  if [[ "$pipeline" == true ]]; then
    # The deploy identity is scoped to the group; it can see it but not create one.
    az group show -n "$rg" -o none
  else
    az group create -n "$rg" -l "$location" --tags claw-instance="$instance" managed-by=bicep -o none
  fi
}

pass_foundation() {
  log "foundation: identities, Key Vaults, registry, network, public IP"
  deploy_template foundation false
  [[ "$what_if" == true ]] || pass_outputs
}

pass_secrets() {
  local kv tmp
  kv="$(foundation_output keyVaultName)"
  log "secrets in $kv"
  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  cleanup_paths+=("$tmp")

  if kv_secret_exists "$kv" ssh-deploy-private-key; then
    echo "ssh-deploy-private-key: present (kept)"
  else
    ssh-keygen -q -t ed25519 -N '' -C "$instance-github-actions" -f "$tmp/deploy_key"
    az keyvault secret set --vault-name "$kv" --name ssh-deploy-private-key --file "$tmp/deploy_key" --content-type "text/plain; openssh-private-key" -o none
    az keyvault secret set --vault-name "$kv" --name ssh-deploy-public-key --value "$(cat "$tmp/deploy_key.pub")" -o none
    echo "ssh-deploy-private-key / ssh-deploy-public-key: generated"
  fi

  if kv_secret_exists "$kv" oauth2-proxy-cookie-secret; then
    echo "oauth2-proxy-cookie-secret: present (kept)"
  else
    # oauth2-proxy decodes the secret as URL-safe base64; standard base64 ('+', '/') would be
    # taken as a raw 44-byte string and rejected ("must be 16, 24, or 32 bytes").
    az keyvault secret set --vault-name "$kv" --name oauth2-proxy-cookie-secret --value "$(openssl rand -base64 32 | tr '+/' '-_')" -o none
    echo "oauth2-proxy-cookie-secret: generated"
  fi

  if [[ -n "${OAUTH_CLIENT_ID:-}" && -n "${OAUTH_CLIENT_SECRET:-}" ]]; then
    az keyvault secret set --vault-name "$kv" --name oauth2-proxy-client-id --value "$OAUTH_CLIENT_ID" -o none
    az keyvault secret set --vault-name "$kv" --name oauth2-proxy-client-secret --value "$OAUTH_CLIENT_SECRET" -o none
    echo "oauth2-proxy-client-id / oauth2-proxy-client-secret: set"
  elif kv_secret_exists "$kv" oauth2-proxy-client-secret; then
    echo "oauth2-proxy-client-*: present (kept)"
  else
    echo "oauth2-proxy-client-*: NOT set — export OAUTH_CLIENT_ID and OAUTH_CLIENT_SECRET" \
      "(hosting/azure/README.md → OAuth client) and rerun this pass before the first deploy."
  fi
  rm -rf "$tmp"
}

pass_vm() {
  log "vm: $vm_name + data disk"
  deploy_template vm true
  [[ "$what_if" == true ]] || echo "public IP: $(foundation_output publicIp)  ($(foundation_output publicFqdn))"
}

host_key() {
  az vm run-command invoke -g "$rg" -n "$vm_name" --command-id RunShellScript \
    --scripts "cat /etc/ssh/ssh_host_ed25519_key.pub" --query "value[0].message" -o tsv \
    | grep -o 'ssh-ed25519 [A-Za-z0-9+/=]*' | head -n1
}

pass_host_key() {
  log "SSH host key of $vm_name"
  local key
  key="$(host_key)"
  [[ -n "$key" ]] || { echo "could not read the host key (is the VM running and provisioned?)" >&2; exit 1; }
  echo "$key"
}

pass_github() {
  local repo client_id tenant host_key_value
  repo="$(github_repository)"
  log "GitHub repository variables + production environment ($repo)"
  client_id="$(foundation_output githubIdentityClientId)"
  tenant="$(az account show --query tenantId -o tsv)"

  # The federated credential is bound to this environment; add reviewers there if deploys
  # should wait for a human.
  gh api --silent -X PUT "repos/$repo/environments/production"

  gh variable set AZURE_CLIENT_ID -R "$repo" -b "$client_id"
  gh variable set AZURE_TENANT_ID -R "$repo" -b "$tenant"
  gh variable set AZURE_SUBSCRIPTION_ID -R "$repo" -b "$AZURE_SUBSCRIPTION_ID"
  gh variable set AZURE_RESOURCE_GROUP -R "$repo" -b "$rg"
  gh variable set SSH_PUBLIC_KEYS -R "$repo" -b "$ssh_public_keys"
  gh variable set SSH_SOURCE_CIDRS -R "$repo" -b "$ssh_source_cidrs"

  if az vm show -g "$rg" -n "$vm_name" -o none 2>/dev/null; then
    host_key_value="$(host_key)"
    [[ -z "$host_key_value" ]] || gh variable set SSH_HOST_PUBLIC_KEY -R "$repo" -b "$host_key_value"
  else
    echo "VM not deployed yet — SSH_HOST_PUBLIC_KEY is set once it exists (rerun this pass or host-key)."
  fi
  gh variable list -R "$repo"
}

pass_outputs() {
  log "outputs ($rg)"
  local o
  for o in githubIdentityClientId keyVaultName runtimeKeyVaultName clawIdentityClientId registryLoginServer registryName networkSecurityGroupName publicIp publicFqdn; do
    printf '%-28s %s\n' "$o" "$(foundation_output "$o" 2>/dev/null || echo '-')"
  done
  echo
  echo "DNS: A ${claw_hostname:-<CLAW_HOSTNAME>} -> $(foundation_output publicIp 2>/dev/null || echo '<public IP>')"
}

case "$pass" in
  group) pass_group ;;
  foundation) pass_foundation ;;
  secrets) pass_secrets ;;
  vm) pass_vm ;;
  host-key) pass_host_key ;;
  github) pass_github ;;
  outputs) pass_outputs ;;
  all) pass_group; pass_foundation; pass_secrets; pass_vm; pass_host_key; pass_github; pass_outputs ;;
  *) echo "unknown pass: $pass" >&2; exit 2 ;;
esac
