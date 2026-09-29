# Extension points

A derived claw should almost never need to edit an upstream-owned file. Each
row below is a seam built for a specific kind of change. If none fits, editing
the upstream file is allowed — it becomes a visible divergence
(`tools/upstream status`) and a candidate for a new seam upstream.

| You want to … | Put it in | Merged how |
|---|---|---|
| name the deployment, pick the profile, list people | `instance/claw.env` | sourced after `hosting/<profile>/profile.env`; wins over it |
| keep a secret | `.secrets/claw.env` (local) or the profile's vault → written there by CI | sourced last; never committed |
| add a CLI, runtime or patch to the image | `instance/image/Dockerfile` | built `FROM` the core image |
| add a service (database, cache, sidecar) | `instance/compose.yml` | Compose merge after core and profile |
| add env, mounts or ports to the gateway | `instance/compose.yml` → `services.claw` | Compose merge; lists append, maps override |
| persist another directory | `instance/compose.yml` + `CLAW_EXTRA_DATA_DIRS` in `instance/claw.env` | `bin/claw init` creates it under the data root |
| define agents, roles, skills, plugins, hooks | `instance/configure.d/NN-name.sh` | runs after every core step, same candidate config |
| override a core configure decision | a later `instance/configure.d/` step | last write wins; validated before publish |
| give an agent instructions | `instance/workspaces/<agent>/` | copied into the workspace on every deploy |
| change the front door (extra route, other IdP) | `instance/compose.yml` (mount your own proxy config over the profile's) | Compose merge |
| change how CI deploys | `.github/workflows/` (copied from `hosting/<profile>/workflows/`) | instance-owned after the copy |

## Rules that keep upgrades cheap

- **Values in `instance/`, mechanisms upstream.** A hostname, an e-mail, a
  registry or a vault name never belongs in an upstream-owned file.
- **Override late, don't edit early.** An instance configure step that re-sets a
  key survives upgrades; an edit to a core step conflicts with every change
  to it.
- **One reason per divergence.** When you must edit an upstream file, keep
  the change minimal and say why in the commit. It is either a backport
  candidate (generic) or a missing seam (tell upstream).
- **Drop, don't delete-and-forget.** Unused hosting profiles may be deleted;
  list them in `UPSTREAM_SKIP` so upgrades don't bring them back.

## Examples of instance extensions

- A development database for an agent that runs a project's test suite:
  a `postgres` service in `instance/compose.yml`, a `.pgpass` mount on the
  gateway, `postgresql-client` in `instance/image/Dockerfile`.
- Private preview hostnames served by the gateway's portal ingress: an
  extra tunnel route in the profile's IaC (a divergence) plus an instance
  configure step setting `gateway.portals.ingress`.
- Sandboxed agents: mount `/var/run/docker.sock` on `claw` and add the
  host's docker group (`group_add`) in `instance/compose.yml`; define the agents'
  `sandbox` blocks in an instance configure step. The core image already carries
  the Docker CLI. Never mount the socket into the sandboxes themselves.
- A runtime vault the agent may read (Azure Key Vault via managed identity,
  1Password service account): the CLI in `instance/image/Dockerfile`, the
  identity or token via `instance/compose.yml` env.
