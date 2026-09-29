# clawfather-boilerplate

A boilerplate for a **team OpenClaw server**: one shared, access-controlled
[OpenClaw](https://github.com/openclaw/openclaw) gateway where a team runs
project work together, instead of each person running a claw on a laptop.

It is meant to be **copied**, not depended on. Every deployment is a derived
repository that owns its own values, agents and hosting choice; the
boilerplate owns the mechanisms. Keeping a copy current is manual but not
blind — see [Upgrading](docs/upgrading.md) and [Backporting](docs/backporting.md).

## Shape

```text
            ┌──────────── hosting/<profile> ────────────┐
people ───▶ │ front door: authenticates, forwards identity │
            └──────────────────────┬──────────────────────┘
                                   │ trusted-proxy (one pinned address)
                    ┌──────────────▼──────────────┐
                    │ claw: OpenClaw gateway       │  core/
                    │  image = core + site layer   │
                    └──────────────┬──────────────┘
                                   │
                        /srv/<instance>  state, workspaces, backups
```

Three layers, composed by one command, `bin/claw`:

| Layer | Path | Owner | What it holds |
|---|---|---|---|
| core | `core/`, `bin/`, `tools/`, `docs/` | boilerplate | gateway runtime contract, image base, configure steps, the CLI |
| hosting profile | `hosting/<profile>/` | boilerplate | provider-native IaC, host bootstrap, front door, workflow templates |
| site | `site/`, `.github/workflows/` | your deployment | values, image additions, extra services, agents, workspaces |

The authoritative ownership map is [`.clawfather/ownership`](.clawfather/ownership).

## Hosting profiles

| Profile | Infra | Front door | Auth | Status |
|---|---|---|---|---|
| [`local`](hosting/local/) | Docker Compose on a workstation | none (loopback) | shared token | runs end to end |
| [`azure`](hosting/azure/) | Bicep: VM, Key Vault, ACR, network | Caddy + oauth2-proxy | trusted-proxy, any OIDC IdP | validated statically |
| [`hetzner-cloudflare`](hosting/hetzner-cloudflare/) | OpenTofu: Hetzner + Cloudflare; Ansible | Cloudflare Tunnel + Access | trusted-proxy, Access identity | validated statically |

Each profile uses its provider's native tooling on purpose: an Azure shop
reviews Bicep, a Cloudflare shop reviews OpenTofu. The runtime is the same
everywhere — Docker Compose driven by `bin/claw`.

## Quick start (local)

```bash
bin/claw deploy          # builds the image, configures, starts, waits for health
bin/claw logs            # follow the gateway
bin/claw open            # Control UI URL, token included
```

Then connect a model provider in the Control UI (Settings → Models). Provider
credentials live in the state volume, not in the repository.

## `bin/claw`

Every operation — on a workstation, on a host over SSH, in CI — goes through
`bin/claw`, so the gateway's env and mounts are defined once
(`core/compose.yml` + profile + site). `bin/claw deploy` is the ordered
rollout: data dirs, image, **verified backup**, workspace sync, **candidate
config** built and validated beside the live one, stop, publish, **offline
doctor**, start, health — and it restores the previous config if the new one
does not come up healthy. `bin/claw --help` lists the rest.

## Deriving your own

[docs/deriving.md](docs/deriving.md). Then:

- [Extension points](docs/extension-points.md) — where each kind of change goes.
- [Upgrading](docs/upgrading.md) — boilerplate → your claw, with `tools/upstream`.
- [Backporting](docs/backporting.md) — your claw → boilerplate, with a leak check.
