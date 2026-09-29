#!/usr/bin/env bash
# Backport leak check: every guard must stop a leaking patch, and a clean
# patch must pass. Builds a throwaway derived repository from this checkout.
# Run: tests/upstream_backport_test.sh   (CI: validate.yml)
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

repo="$work/derived"
mkdir -p "$repo"
cp -R "$src/bin" "$src/tools" "$src/.clawfather" "$src/docs" "$repo/"
mkdir -p "$repo/hosting" "$repo/instance"
cp -R "$src/hosting/local" "$repo/hosting/"
sed 's/^CLAW_INSTANCE=.*/CLAW_INSTANCE=secretclaw/' "$src/instance/claw.env.example" > "$repo/instance/claw.env"
printf 'orchid-internal\n' > "$repo/.clawfather/private-terms"
rm -f "$repo/.clawfather/public-emails"

cd "$repo"
git init -q
git config user.name "Test Publisher"
git config user.email "publisher@example.com"
git add -A && git commit -qm base
printf 'UPSTREAM_URL=%s\nUPSTREAM_REF=%s\nUPSTREAM_SKIP=""\n' "$src" "$(git rev-parse HEAD)" > .clawfather/upstream.env
git add -A && git commit -qm state

# probe NAME EXPECT(pass|fail) TEXT [AUTHOR] — one commit touching docs/.
probe() {
  local name="$1" expect="$2" text="$3" author="${4:-}" out status=0
  git checkout -q -B "probe-$name" main 2>/dev/null || git checkout -q -B "probe-$name"
  printf '%s\n' "$text" >> docs/upgrading.md
  if [[ -n "$author" ]]; then
    git -c user.name="${author% <*}" -c user.email="$(sed 's/.*<\(.*\)>/\1/' <<<"$author")" commit -qam "docs: $name"
  else
    git commit -qam "docs: $name"
  fi
  out="$work/out-$name"
  tools/upstream backport HEAD^! -o "$out" >/dev/null 2>&1 || status=$?
  if [[ "$expect" == pass && $status -eq 0 ]] || [[ "$expect" == fail && $status -ne 0 ]]; then
    echo "ok: $name ($expect)"
  else
    echo "FAIL: $name expected $expect, got status $status"; failures=$((failures + 1))
  fi
  if [[ "$name" == private-author && $status -eq 0 ]]; then
    grep -q '^From: Test Publisher <publisher@example.com>' "$out"/*.patch ||
      { echo "FAIL: author not rewritten"; failures=$((failures + 1)); }
  fi
  git checkout -q main 2>/dev/null || git checkout -q master
}
git branch -M main

probe clean pass "Generic wording only."
probe private-email fail "contact someone@private-corp.test"
probe single-label-email fail "contact someone@private-corp"
probe punycode-email fail "contact someone@xn--private-corp"
probe public-noreply pass "Co-Authored-By: Bot <noreply@anthropic.com>"
probe example-email pass "ops@example.com"
probe instance-name fail "runs on secretclaw"
probe private-term fail "the orchid-internal project"
probe private-author pass "Generic again." "Private Colleague <colleague@private-corp.test>"

# Use a known docs-changing commit with valid patterns. This must fail only
# because the requested output directory already contains a patch.
mkdir -p "$work/stale" && touch "$work/stale/old.patch"
git checkout -q probe-clean
if tools/upstream backport HEAD^! -o "$work/stale" >/dev/null 2>&1; then
  echo "FAIL: non-empty output directory accepted"; failures=$((failures + 1))
else
  echo "ok: stale output directory refused"
fi
git checkout -q main

printf '(unclosed\n' >> .clawfather/private-terms && git commit -qam "bad pattern"
printf 'UPSTREAM_URL=%s\nUPSTREAM_REF=%s\nUPSTREAM_SKIP=""\n' "$src" "$(git rev-parse HEAD)" > .clawfather/upstream.env
git commit -qam "rebase state"
probe malformed-pattern fail "Generic text."

((failures == 0)) || { echo "$failures failure(s)"; exit 1; }
echo "all backport checks passed"
