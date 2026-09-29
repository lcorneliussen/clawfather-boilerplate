# AGENTS.md — clawfather-boilerplate

Read `README.md` first. This repository is the **public boilerplate**; derived
claws are private copies of it.

## Rules

1. **Public.** Nothing here names a real deployment, organisation, domain,
   person, vault or account. Examples use `example.com`, `claw.example.com`,
   `teamclaw`. Issues, PRs and review replies follow the same rule — a fix
   backported from a derived claw is described generically.
2. **Mechanisms here, values in `site/`.** An upstream-owned file never holds
   a deployment's value. If a change needs one, add a variable (read from
   `site/claw.env`) or a seam (`docs/extension-points.md`).
3. **One runtime contract.** Gateway env and mounts live only in
   `core/compose.yml` (plus profile/site overlays). Anything that runs
   OpenClaw goes through `bin/claw`; never write another `docker run` with
   the contract spelled out.
4. **Configuration is a candidate first.** Configure steps write to the
   candidate config; `bin/claw deploy` publishes it only while the gateway is
   stopped, after validation.
5. **Pin versions.** OpenClaw, CLIs (with checksums), proxy and tunnel images,
   IaC providers. A bump is its own commit.
6. **Commit subjects name the seam** — `core:`, `bin:`, `hosting/azure:`,
   `hosting/hetzner-cloudflare:`, `hosting/local:`, `tools:`, `docs:`, `site:`
   — and a change that requires derived claws to act carries a
   **Site action:** paragraph in the body. Derived claws read these through
   `tools/upstream status`.
7. **Ownership map is a contract.** Moving or renaming an upstream-owned path
   breaks derived upgrades; do it only with a Site action note.

## Checks

`tools/check` runs what CI runs: shellcheck, compose config for every
profile, the configure steps' syntax, and the profile validators.
