# Upgrading a derived claw

Upgrades are manual on purpose — a claw is production infrastructure, and
every upstream change should be read before it lands. `tools/upstream`
makes the reading and the applying cheap.

```bash
tools/upstream status        # upstream commits since your base; your divergences
tools/upstream diff          # the change itself, owned paths only
git switch -c upstream-<short-sha>
tools/upstream apply         # 3-way apply + new base recorded, all staged
bin/claw deploy              # locally, with CLAW_PROFILE=local, if you can
git commit                   # message suggested by apply
```

Then open a PR as for any other change; the deploy workflow rolls it out.

## How it works

- `.clawfather/upstream.env` records `UPSTREAM_REF`, the boilerplate commit
  your copy last took. It is the merge base.
- `apply` computes `UPSTREAM_REF..<target>` on upstream-owned paths
  (`.clawfather/ownership`, minus `UPSTREAM_SKIP`) and applies it with
  `git apply --3way`. Where you diverged, you get conflict markers, exactly
  as in a merge. Site-owned paths are never touched.
- Changes to `site/*.example` and the `site/**/README.md` files arrive too;
  compare them with your own `site/` files by hand — that is where new
  settings show up.
- `hosting/<profile>/workflows/` changes arrive in the templates, not in
  your `.github/workflows/`. Diff and port them by hand:
  `diff -u hosting/<profile>/workflows/deploy.yml .github/workflows/deploy.yml`.

## Target must be ahead of your base

`status`, `diff` and `apply` refuse a target that does not contain your
base commit — applying "backwards" would revert upstream work. While your
base sits on an unmerged boilerplate branch, name that branch:
`tools/upstream status <branch>`.

## Pin to a release

`tools/upstream apply <tag-or-sha>` takes a specific boilerplate commit
instead of `main`.

## Reading upstream history

Commits in the boilerplate name the seam they touch in the subject
(`core:`, `hosting/azure:`, `tools:`, `docs:`) and call out anything that
needs a site action under **Site action:** in the body. `status` lists them.
