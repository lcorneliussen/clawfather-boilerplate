# Deriving a claw

A derived claw is a **copy** of this repository that keeps the upstream
history, so later upgrades are ordinary 3-way applies.

```bash
git clone https://github.com/lcorneliussen/clawfather-boilerplate.git my-claw
cd my-claw
git remote rename origin boilerplate      # optional: handy for browsing
git remote add origin git@github.com:<owner>/my-claw.git
tools/upstream init                        # records the base commit
```

Then make it yours:

1. **`site/claw.env`** — `CLAW_PROFILE`, `CLAW_INSTANCE`, hostname, people.
2. **Drop unused profiles** — delete `hosting/<other>/` and list them in
   `UPSTREAM_SKIP` in `.clawfather/upstream.env`.
3. **Workflows** — copy `hosting/<profile>/workflows/*.yml` into
   `.github/workflows/`. From then on they are yours.
4. **`README.md` / `AGENTS.md`** — rewrite for this deployment: what it is
   for, who runs it, where its secrets live. Link `docs/` for the generic
   parts instead of copying them.
5. **Agents** — `site/configure.d/` and `site/workspaces/`.
6. Commit: `derive: from clawfather-boilerplate <short-sha>`.

Try it locally first, whatever the eventual profile:

```bash
CLAW_PROFILE=local CLAW_DATA=.data bin/claw deploy
open http://127.0.0.1:18789        # token: .secrets/claw.env
```

A derived repository is usually **private**. The boilerplate is public: see
[backporting.md](backporting.md) before anything flows back.
