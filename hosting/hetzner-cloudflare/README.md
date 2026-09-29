# Profile: hetzner-cloudflare

One Hetzner Cloud host runs the compose stack: the gateway from
`core/compose.yml` plus a Cloudflare Tunnel connector from this profile. The
host publishes no HTTP port. People reach the Control UI through Cloudflare
Access. CI and operators reach sshd through the same tunnel, also behind
Access.

```text
 browser ──https──▶ Cloudflare Access ─┐                       Hetzner host
 (claw.example.com)  (e-mail allowlist) │   tunnel (outbound)   ┌──────────────────────────────────────┐
                                        ├──────────────────────▶│ cloudflared 172.30.0.10 ─┐           │
 CI / operator ──ssh──▶ Access ─────────┘                       │   │ http://claw:18789    │ ssh://    │
 (ssh.example.com)  (service token                              │   ▼                      ▼ host.docker│
                     or e-mail)                                 │ claw (gateway)        sshd  .internal│
                                                                │   trusts 172.30.0.10 only             │
                                                                │   /srv/<instance>  ◀── Hetzner volume │
                                                                │   /opt/<instance>  ◀── repo checkout  │
                                                                └──────────────────────────────────────┘
 Hetzner firewall: inbound 22 only from ssh_source_cidrs (recovery), nothing else.
```

The gateway runs in `trusted-proxy` mode (`profile.env`). It accepts identity
headers only from cloudflared's pinned address, and it requires the Access
JWT header. It also repeats the Access e-mail allowlist as a second fence.

## Who owns what

| Path | Owner | What it is |
| --- | --- | --- |
| `hosting/hetzner-cloudflare/profile.env` | upstream | auth mode and proxy trust for this front door |
| `hosting/hetzner-cloudflare/compose.yml` | upstream | the `cloudflared` service |
| `hosting/hetzner-cloudflare/infra/*.tf` | upstream | Hetzner server, volume, firewall; tunnel, DNS, Access |
| `hosting/hetzner-cloudflare/ansible/` | upstream | host bootstrap: hardening, Docker, deploy user, mounts |
| `hosting/hetzner-cloudflare/workflows/*.yml` | upstream | templates; copy them to `.github/workflows/` |
| `site/claw.env` | site | instance, hostname, people: read by the gateway **and** by OpenTofu |
| `site/infra/terraform.tfvars` | site | the remaining non-secret OpenTofu inputs (from `infra/terraform.tfvars.example`) |
| `site/infra/backend.hcl` | site | state bucket, no credentials (from `infra/backend.hcl.example`) |
| `.github/workflows/{infrastructure,deploy}.yml` | site copy | re-copy after a boilerplate upgrade; keep local edits minimal |
| `ansible/inventory.yml` | operator | local, ignored; from `inventory.example.yml` |
| `/opt/<instance>/.secrets/claw.env` | deploy workflow | written on every deploy; never edit it on the host |

## What goes where

| Value | Where | Used by |
| --- | --- | --- |
| `CLAW_PROFILE=hetzner-cloudflare`, `CLAW_INSTANCE`, `CLAW_HOSTNAME`, `CLAW_ACCESS_EMAILS`, `CLAW_ADMIN_EMAILS` | `site/claw.env` | gateway config, Access policy (infrastructure workflow maps them to `TF_VAR_*`) |
| zone, account and zone IDs, bootstrap SSH key, `ssh_source_cidrs`, server size, IdP IDs | `site/infra/terraform.tfvars` | OpenTofu |
| `CLAW_SSH_HOSTNAME`, `SSH_HOST_PUBLIC_KEY`, optional `CLAW_DEPLOY_USER`, `CLAW_PLATFORM` | repository variables | deploy workflow |
| `HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN`, `TOFU_STATE_ACCESS_KEY_ID`, `TOFU_STATE_SECRET_ACCESS_KEY`, optional `GITHUB_OAUTH_CLIENT_ID` / `_SECRET` | `production` environment secrets | infrastructure workflow |
| `DEPLOY_SSH_PRIVATE_KEY`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`, `CLOUDFLARE_TUNNEL_TOKEN`, optional `CLAW_SECRETS_ENV` | `production` environment secrets | deploy workflow → host `.secrets/claw.env` |

`CLAW_SECRETS_ENV` holds any further runtime secrets, such as model provider
keys. Write it as shell-quoted `KEY=value` lines, because `bin/claw` sources
the file. The workflow runs `bash -n` on it before shipping.

Both workflows mark where 1Password could replace environment secrets:
`1password/load-secrets-action` with a service account. That is optional and
commented out.

## Bring-up order

1. **OpenTofu.** Create `site/infra/backend.hcl` and
   `site/infra/terraform.tfvars` from the examples. Set
   `CLAW_PROFILE=hetzner-cloudflare` and `CLAW_HOSTNAME` in `site/claw.env`,
   then run the *Infrastructure* workflow: first `plan`, then `apply`. To run
   it from a workstation instead:

   ```sh
   cd hosting/hetzner-cloudflare/infra
   set -a; . ../../../site/claw.env; set +a
   export TF_VAR_instance="$CLAW_INSTANCE" TF_VAR_claw_hostname="$CLAW_HOSTNAME" \
          TF_VAR_claw_access_emails="$CLAW_ACCESS_EMAILS"
   tofu init -backend-config=../../../site/infra/backend.hcl
   tofu plan -var-file=../../../site/infra/terraform.tfvars -out=plan && tofu apply plan
   ```

   Copy the sensitive outputs into the `production` environment:
   `cloudflare_tunnel_token` becomes `CLOUDFLARE_TUNNEL_TOKEN`, and
   `ci_access_client_id` / `ci_access_client_secret` become
   `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET`. Set
   `CLAW_SSH_HOSTNAME` from `tofu output ssh_hostname`.

2. **Ansible.** Generate a CI deploy key pair (`ssh-keygen -t ed25519`). Its
   private half becomes `DEPLOY_SSH_PRIVATE_KEY`; its public half goes into
   `deploy_authorized_keys` with the operators' keys. Fill `inventory.yml`
   (public IP, root, `volume_linux_device`), then run from a CIDR listed in
   `ssh_source_cidrs`:

   ```sh
   cd hosting/hetzner-cloudflare/ansible
   ansible-galaxy collection install -r requirements.yml
   ansible-playbook site.yml
   ```

   Record the host key as the `SSH_HOST_PUBLIC_KEY` variable:
   `ssh root@<ip> cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub`.

3. **Light the tunnel once.** CI deploys through the tunnel, and the tunnel
   is part of the stack that the deploy starts. The very first start therefore
   has to happen over the recovery path:

   ```sh
   rsync -az --exclude=/.git --exclude=/.data --exclude=/.secrets ./ deploy@<ip>:/opt/<instance>/
   tofu -chdir=hosting/hetzner-cloudflare/infra output -raw cloudflare_tunnel_token \
     | ssh deploy@<ip> 'umask 077; mkdir -p /opt/<instance>/.secrets;
         { printf "CLOUDFLARE_TUNNEL_TOKEN="; cat; echo; } > /opt/<instance>/.secrets/claw.env'
   ssh deploy@<ip> 'cd /opt/<instance> && bin/claw compose up -d --no-deps cloudflared'
   ```

   `ssh <ssh hostname>` with `ProxyCommand cloudflared access ssh --hostname %h`
   now works. After that, `ssh_source_cidrs` can be emptied to close port 22
   entirely; the Hetzner console remains the last resort.

4. **Deploy.** Push to `main` or run the *Deploy* workflow. It builds and pushes
   `ghcr.io/<owner>/<repo>-openclaw:<sha>`, syncs the repository to
   `/opt/<instance>`, and writes `.secrets/claw.env`. It then pulls the image
   with a job-scoped registry login and runs
   `CLAW_IMAGE=… CLAW_BUILD=no bin/claw deploy` as a transient systemd unit. A
   systemd unit survives the SSH session, which matters when the rollout
   recreates cloudflared. Later host changes (packages, keys) go through
   Ansible again, over the tunnel (see `inventory.example.yml`).

## Rollback

- **Failed rollout.** `bin/claw deploy` restores the previous gateway config
  and starts the gateway again. The job fails, and the unit's journal is in
  the job log.
- **Bad image or config change.** `git revert` and push; the revert deploys
  like any change. The fast path on the host: previous images stay in the local
  image store, so run
  `CLAW_IMAGE=ghcr.io/<owner>/<repo>-openclaw:<old-sha> CLAW_BUILD=no bin/claw deploy`
  in `/opt/<instance>`. Expect the next workflow deploy to overwrite it, and
  revert in git as well.
- **State.** Every deploy writes a verified backup to
  `/srv/<instance>/backups` before touching config. The volume outlives the
  server: it has delete protection and `prevent_destroy`.
- **Infrastructure.** Revert the change, then plan and apply. The server and
  volume carry delete and rebuild protection and `prevent_destroy`. Replacing
  either is a deliberate, multi-step act, never a side effect of a plan.
- **Locked out of SSH through Access.** Add your CIDR to `ssh_source_cidrs`
  and apply, then use the public IP. Or use the Hetzner console.

## Extending

`extra_ingress` adds tunnel routes ahead of the catch-all 404. A site that
serves more hostnames adds them there. One example is a wildcard
`*.example.com` for per-agent portals served by a sidecar in
`site/compose.yml`. The site adds its DNS records and an Access application
for the new hostnames in its own OpenTofu next to them; the boilerplate ships
none of that.

## Local checks

```sh
# OpenTofu (no credentials needed)
docker run --rm -v "$PWD/hosting/hetzner-cloudflare/infra:/w" -w /w --entrypoint sh \
  ghcr.io/opentofu/opentofu:1.12.6 -c 'tofu fmt -check && tofu init -backend=false && tofu validate; rm -rf .terraform'

# Ansible
cd hosting/hetzner-cloudflare/ansible && ANSIBLE_CONFIG=ansible.cfg \
  ansible-playbook --syntax-check -i inventory.example.yml site.yml

# Workflow templates (SC2029 flags remote commands built client-side on purpose)
actionlint -ignore SC2029 hosting/hetzner-cloudflare/workflows/*.yml

# The merged compose stack for this profile
CLOUDFLARE_TUNNEL_TOKEN=dummy bin/claw compose config
```
