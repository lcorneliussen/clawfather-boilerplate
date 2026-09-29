# Hosting profile: azure

One Azure VM runs the claw with Docker Compose. Caddy terminates TLS,
oauth2-proxy signs people in, and the gateway trusts exactly Caddy's pinned
address. CI builds the image, ships this repository to the host and runs
`bin/claw deploy` there: the same command an operator runs by hand.

```text
                    ┌──────────────── VM vm-<instance> (Ubuntu 24.04) ─────────────────┐
 browser ──443──▶   │ caddy 172.30.0.10 ──forward auth──▶ oauth2-proxy :4180            │
                    │   │  (X-Auth-Request-Email/User)       │ Google (or another IdP)  │
                    │   └──────────────▶ claw :18789 ◀── 127.0.0.1:18789 (operations)   │
                    │                        │                                          │
                    │   /opt/<instance>   repository checkout (rsync from CI)           │
                    │   /srv/<instance>   data disk: state, workspaces, backups, certs  │
                    └────────────────────────┬─────────────────────────────────────────┘
                                             │ user-assigned identity id-claw-<instance>
                                             ▼
                                   runtime Key Vault (agent may read)

 GitHub Actions ──OIDC──▶ id-github-<instance>: Contributor on rg-<instance>,
                          AcrPush on the registry, reads the deploy Key Vault
```

| File | Role |
|---|---|
| `profile.env` | trusted-proxy auth, Caddy's pinned address, front-door data directories |
| `compose.yml` | `caddy` and `oauth2-proxy`, merged after `core/compose.yml` |
| `caddy/Caddyfile` | forward auth, header stripping, `/healthz` passthrough |
| `infra/` | Bicep: foundation pass (identities, two Key Vaults, registry, network, IP) and VM pass (VM, locked data disk, cloud-init) |
| `bootstrap.sh` | operator bring-up, one idempotent pass at a time |
| `workflows/` | templates for `.github/workflows/` — `deploy.yml`, `infrastructure.yml` |

Everything here is upstream-owned. Site changes go through the seams in
[docs/extension-points.md](../../docs/extension-points.md): a different
Caddyfile is a directory mounted over `/etc/caddy` from `site/compose.yml`,
another identity provider is `CLAW_OAUTH_PROVIDER` plus any provider-specific
`OAUTH2_PROXY_*` env on `oauth2-proxy` in `site/compose.yml`.

## Where values go

| Value | Where | Why there |
|---|---|---|
| `CLAW_PROFILE=azure`, `CLAW_INSTANCE`, `CLAW_HOSTNAME` | `site/claw.env` | names every Azure resource (`rg-<instance>`, `vm-<instance>` …), the data root and the public host |
| `CLAW_ACME_EMAIL` | `site/claw.env` | Let's Encrypt contact; Caddy refuses to start without it |
| `CLAW_ACCESS_DOMAINS` | `site/claw.env` | comma-separated e-mail domains anyone in which may sign in; empty = allowlist only |
| `CLAW_ACCESS_EMAILS`, `CLAW_ADMIN_EMAILS` | `site/claw.env` | JSON arrays; the deploy writes the first to oauth2-proxy's allowlist, the second becomes `operator.admin` |
| `CLAW_OAUTH_PROVIDER` | `site/claw.env` | oauth2-proxy provider, default `google` |
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP` | repository variables | OIDC login of the workflows (`bootstrap.sh github`) |
| `SSH_HOST_PUBLIC_KEY`, `SSH_PUBLIC_KEYS`, `SSH_SOURCE_CIDRS` | repository variables | pinned host key; operator keys and CIDRs for the VM pass |
| CI SSH key pair, OAuth client id/secret, cookie secret | deploy Key Vault | read by the deploy identity; written to the host's `.secrets/claw.env` on every deploy |
| secrets the agent itself may use | runtime Key Vault | read live by the VM identity; nothing from the deploy vault is ever copied here |
| model-provider keys | Control UI → Settings → Models | stored in the gateway state on the data disk |

Sign-in needs at least one of `CLAW_ACCESS_DOMAINS` / `CLAW_ACCESS_EMAILS`;
either one admits a person. The gateway does not repeat the allowlist
(`CLAW_GATEWAY_ALLOWLIST=no`), because it cannot express domains.

## Bring-up order

Prerequisites: `az` (logged in, Owner or User Access Administrator on the
subscription for the role assignments), `gh` (authenticated for the derived
repository), `jq`, `ssh-keygen`, `openssl`. Copy the workflow templates first:

```bash
cp hosting/azure/workflows/*.yml .github/workflows/
export AZURE_SUBSCRIPTION_ID=<subscription id>
export SSH_PUBLIC_KEYS='["ssh-ed25519 AAAA… you@laptop"]'   # optional: operator access
export SSH_SOURCE_CIDRS='["203.0.113.4/32"]'                 # optional: operator access
```

1. **`site/claw.env`** — set `CLAW_PROFILE=azure`, `CLAW_INSTANCE`,
   `CLAW_HOSTNAME`, `CLAW_ACME_EMAIL`, the people; commit.
2. **`hosting/azure/bootstrap.sh group`**, then **`foundation`** — resource
   group, identities, both Key Vaults, registry, network and the static
   public IP. Prints the IP.
3. **DNS** — an A record at your DNS provider: `CLAW_HOSTNAME` → the public
   IP. Use the IP, not a CNAME to the Azure-generated `*.cloudapp.azure.com`
   name; Let's Encrypt validates the name the browser uses. The IP is
   detached, not deleted, with the VM, so the record survives rebuilds.
4. **OAuth client** (see below), then **`bootstrap.sh secrets`** with
   `OAUTH_CLIENT_ID` / `OAUTH_CLIENT_SECRET` exported. Generates the CI SSH
   key and the cookie secret on first run.
5. **`bootstrap.sh vm`** — the VM and its data disk. cloud-init installs
   Docker and mounts `/srv/<instance>`; give it a few minutes.
6. **`bootstrap.sh github`** — repository variables, including the VM's
   SSH host key, and the `production` environment.
7. **Push to `main`** (or run *Deploy* by hand). The first run creates the
   data directories, pulls the images and starts all three services.

`bootstrap.sh all` runs steps 2–6 in one go once the OAuth client exists.
Later infrastructure changes (VM size, SSH keys) go through the
*Infrastructure* workflow: `what-if` first, then `apply`.

### OAuth client (Google)

In a Google Cloud project: **OAuth consent screen** — audience *External*
(Internal would limit sign-in to one Workspace and rule out an allowlist for
outside collaborators); with only `openid`, `email`, `profile` no
verification review is needed. **Credentials → OAuth client ID** — type
*Web application*, origin `https://claw.example.com`, redirect URI
`https://claw.example.com/oauth2/callback`. Store the id and secret with
`bootstrap.sh secrets`; nothing is kept in GitHub.

## Operating

```bash
RG=rg-<instance>
HOST=$(az deployment group show -g $RG -n foundation --query properties.outputs.publicFqdn.value -o tsv)
ssh deploy@$HOST 'cd /opt/<instance> && bin/claw status'      # needs your CIDR in SSH_SOURCE_CIDRS
ssh deploy@$HOST 'cd /opt/<instance> && bin/claw logs caddy'  # or oauth2-proxy, claw
```

Without SSH (Contributor on the group is enough):

```bash
az vm run-command invoke -g $RG -n vm-<instance> --command-id RunShellScript \
  --scripts 'docker logs --tail 200 <instance>-claw' --query 'value[0].message' -o tsv
```

What to look for:

- oauth2-proxy `403` for a person → not in `CLAW_ACCESS_DOMAINS` /
  `CLAW_ACCESS_EMAILS`.
- gateway `proxy_attribution_required` → a request reached the gateway from
  somewhere other than Caddy's pinned address, or without a usable
  `X-Forwarded-For`. Check `docker inspect <instance>-caddy` and the
  Caddyfile's header handling.
- Caddy `obtaining certificate … failed` → DNS not pointing at the VM yet, or
  80/443 blocked. Caddy retries with back-off; the *Deploy* workflow prints a
  notice instead of failing while DNS is elsewhere.

| Change | How |
|---|---|
| people, domains | edit `site/claw.env`, push — oauth2-proxy picks up the allowlist file live |
| OpenClaw version | bump `OPENCLAW_IMAGE` in `site/claw.env`, push |
| Caddy / oauth2-proxy version | bump the tag in `compose.yml` (an upstream change) |
| rotate the OAuth client secret | new secret in the IdP → `bootstrap.sh secrets` → *Deploy* → delete the old one |
| rotate the cookie secret | `az keyvault secret set … -n oauth2-proxy-cookie-secret --value "$(openssl rand -base64 32 \| tr '+/' '-_')"` → *Deploy* (signs everyone out) |
| rotate the CI SSH key | delete both `ssh-deploy-*` secrets, `bootstrap.sh secrets`, then *Infrastructure* → `apply` / `vm` |

Every deploy takes a verified backup into `/srv/<instance>/backups` before
touching the gateway, runs `doctor --fix` with the gateway stopped and
restores the previous config if the new one does not come up healthy (see
`bin/claw help`). Do not run `openclaw update` on the host; bump the image.

### Backups and rebuilds

- **Disk snapshots** (recommended, nightly, keep ≥ 7):
  `az snapshot create -g $RG -n disk-<instance>-data-$(date +%F) --source disk-<instance>-data --incremental true`,
  automated with an Azure Backup policy or a scheduled workflow.
- The data disk carries a `CanNotDelete` lock: deleting the resource group
  fails on purpose until someone removes it by hand.
- **Rebuilding the VM**: `az vm delete -g $RG -n vm-<instance> --yes` (OS disk
  and NIC go; data disk and IP stay) → `bootstrap.sh vm` (cloud-init finds the
  filesystem and mounts it without formatting) → `bootstrap.sh github` (new
  host key) → *Deploy*.

### SSH recovery

- Locked out: add your CIDR to `SSH_SOURCE_CIDRS` and run *Infrastructure* →
  `apply` / `vm`, or add a temporary NSG rule (priority 250, your `/32`) and
  delete it afterwards.
- Lost keys: `az vm user update -g $RG -n vm-<instance> -u deploy --ssh-key-value "$(cat ~/.ssh/id_ed25519.pub)"`,
  or the serial console.
- An *Infrastructure* apply rewrites the NSG rule set and drops a running
  deploy's temporary `ci-ssh-*` rule; rerun that deploy.

### Runtime secrets for the agent

The gateway container gets `AZURE_CLIENT_ID` (the VM's runtime identity) and
`AZURE_KEYVAULT_NAME` (the runtime vault). With the Azure CLI added in
`site/image/Dockerfile`:

```bash
az keyvault secret set --vault-name <runtime vault> -n some-api-token --value '…'   # operator
az login --identity --client-id "$AZURE_CLIENT_ID" --allow-no-subscriptions -o none  # agent
az keyvault secret show --vault-name "$AZURE_KEYVAULT_NAME" -n some-api-token --query value -o tsv
```

Whatever is in that vault is readable by every prompt the agent runs. Grant
the runtime identity further Azure roles only through a reviewed change to
`infra/`.

## Local checks

```bash
az bicep build --file hosting/azure/infra/main.bicep --stdout >/dev/null
bash -n hosting/azure/bootstrap.sh
CLAW_PROFILE=azure CLAW_HOSTNAME=claw.example.com CLAW_ACME_EMAIL=ops@example.com \
  OAUTH2_PROXY_CLIENT_ID=x OAUTH2_PROXY_CLIENT_SECRET=x OAUTH2_PROXY_COOKIE_SECRET=x \
  bin/claw compose config >/dev/null
docker run --rm -e ACME_EMAIL=ops@example.com -e CLAW_HOSTNAME=claw.example.com \
  -v "$PWD/hosting/azure/caddy:/etc/caddy:ro" docker.io/library/caddy:2.11.4 \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
hosting/azure/bootstrap.sh foundation --what-if      # against a real subscription
```
