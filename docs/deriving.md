# Deriving a claw

A derived claw is a **copy** of this repository that keeps the upstream
history, so later upgrades are ordinary 3-way applies.

```bash
git clone https://github.com/lcorneliussen/clawfather-boilerplate.git my-claw
cd my-claw
git remote rename origin boilerplate      # optional: handy for browsing
git remote add origin git@github.com:<owner>/my-claw.git
tools/upstream init --skip hosting/azure  # base commit + profiles you drop
```

Deriving into a repository that already has history (a README from the
forge, an older deployment) works the same way after one merge:

```bash
git fetch https://github.com/lcorneliussen/clawfather-boilerplate.git main
git merge --allow-unrelated-histories FETCH_HEAD
tools/upstream init --ref main --skip hosting/azure
```

Then make it yours:

1. **`site/claw.env`** — `CLAW_PROFILE`, `CLAW_INSTANCE`, hostname, people.
2. **Drop unused profiles** — delete `hosting/<other>/`; `init --skip`
   recorded them as `UPSTREAM_SKIP` in `.clawfather/upstream.env`.
3. **Workflows** — copy `hosting/<profile>/workflows/*.yml` into
   `.github/workflows/`. From then on they are yours.
4. **`README.md` / `AGENTS.md`** — rewrite for this deployment: what it is
   for, who runs it, where its secrets live. Link `docs/` for the generic
   parts instead of copying them.
5. **Agents** — `site/configure.d/` and `site/workspaces/`.
6. **Private terms** — your project's, organisation's and domains' names in
   `.clawfather/private-terms`, so a backport can never carry them
   ([publication-guard.md](publication-guard.md)).
7. Commit: `derive: from clawfather-boilerplate <short-sha>`.

Try it locally first, whatever the eventual profile:

```bash
CLAW_PROFILE=local CLAW_DATA=.data bin/claw deploy
bin/claw open                      # Control UI URL with the token
```

A derived repository is usually **private**. The boilerplate is public: see
[backporting.md](backporting.md) before anything flows back.
