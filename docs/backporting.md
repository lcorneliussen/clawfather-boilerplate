# Backporting to the boilerplate

A derived claw is where rough edges are found. A fix that would help any
claw belongs upstream — otherwise every derived copy drifts in its own
direction.

**Generic or specific?** A change is generic when it would make sense in a
claw that has never heard of yours: a bug in `bin/claw`, a hardening option,
a missing configure helper, a better health check, a new seam. It is
specific when it names your people, hosts, vaults, agents or products —
those stay in `instance/`.

## Flow

In the derived repository, keep the generic change in its own commit(s)
touching only upstream-owned paths. Then:

```bash
tools/upstream divergence                       # what you changed on owned paths
tools/upstream backport <sha>^! -o /tmp/bp      # or a range: A..B
```

`backport` exports the commits limited to upstream-owned paths, rewrites
their author to you (`--author` to choose), and runs the **leak check** over
each whole patch — see [publication-guard.md](publication-guard.md). A hit
stops the export. `-o` must name a new or empty directory.

In a boilerplate checkout:

```bash
git switch -c <slug>
git am -3 /tmp/bp/*.patch
bin/claw deploy                                  # local profile smoke test
```

Open a PR on the boilerplate. The boilerplate is **public**: the PR title,
body and review replies must not name the private deployment the change came
from, nor who uses the boilerplate. Describe the problem generically.

Once merged, `tools/upstream apply` in the derived repository brings the
change back as upstream's; your local copy of it resolves cleanly because the
content is identical.

## What a leak check cannot do

It matches patterns; it does not understand meaning. A log line, a
screenshot, a comment that describes "our billing system" — read the patch
before you send it.
