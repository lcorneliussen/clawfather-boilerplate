# Keeping private names out of the boilerplate

The boilerplate is public; the claws derived from it are usually not. Their
names — projects, organisations, domains, hosts, people — must never appear
in shared code, in its history, or in its issues and PRs. Two guards, one on
each side of the boundary:

## Before it leaves: `tools/upstream backport` (derived side)

Every backport is checked as a whole patch — author header, message, diff —
against the instance's instance, hostname and image name (`instance/claw.env`),
the instance's `.clawfather/private-terms` (one extended regex per line), and
every e-mail address that is not explicitly public. The author is rewritten
to the publisher's identity, so private contributors never reach the public
history. Any hit, or a pattern that cannot be parsed, stops the export.

Put the derived project's own name in `.clawfather/private-terms` first
thing after deriving — the leak check can only refuse what it knows.

## After it arrives: the publication guard (boilerplate side)

`.github/workflows/publication-guard.yml` scans every PR (title, body,
branch, commit messages, changed file names and complete contents), issue,
comment and review for the literal terms in the repository secret
`PUBLICATION_FORBIDDEN_TERMS` (one per line; NFKC-normalised, case-folded).
A match fails the check with a generic message — no term, snippet or file
name is printed. Missing configuration and API trouble fail closed too.

Maintainers keep the term list in the secret only — never in files, command
arguments, fixtures or PR discussion:

```bash
gh secret set PUBLICATION_FORBIDDEN_TERMS -R <owner>/clawfather-boilerplate < private-terms.txt
```

The workflow runs default-branch code (`pull_request_target`), so it only
takes effect once merged to `main`. After changing the secret, re-run it on a
clean PR (`workflow_dispatch`) to confirm it still passes.

## What neither can do

Both match text. Neither understands a paraphrase ("our billing product"),
reads images or archives, or removes anything once published: the guard
detects after publication, it does not prevent it. Read what you publish.

Ported from wtc-boilerplate's publication guard. `tools/publication-guard.py`
and `tests/publication_guard_test.py` match it except that commit author and
committer identities are scanned too; keep the two in step.
