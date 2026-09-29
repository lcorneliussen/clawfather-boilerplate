#!/usr/bin/env bash
# Exercise upgrades in isolated repositories, including a changed target tool.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
upstream="$work/upstream"
mkdir -p "$upstream/tools" "$upstream/.clawfather" "$upstream/docs"
cp "$src/tools/upstream" "$upstream/tools/upstream"
printf 'upstream:tools/\nupstream:docs/\n' > "$upstream/.clawfather/ownership"
printf 'start\n' > "$upstream/docs/probe.md"
git -C "$upstream" init -q -b main
git -C "$upstream" config user.name Test
git -C "$upstream" config user.email test@example.com
git -C "$upstream" add -A
git -C "$upstream" commit -qm initial
old="$(git -C "$upstream" rev-parse HEAD)"
touch "$upstream/docs/base.md"
git -C "$upstream" add -A
git -C "$upstream" commit -qm base
base="$(git -C "$upstream" rev-parse HEAD)"

make_derived() {
  git clone -q "$upstream" "$1"
  git -C "$1" config user.name Test
  git -C "$1" config user.email test@example.com
  printf 'UPSTREAM_URL=%s\nUPSTREAM_REF=%s\nUPSTREAM_SKIP=""\n' \
    "$upstream" "$base" > "$1/.clawfather/upstream.env"
  git -C "$1" add -A
  git -C "$1" commit -qm 'record base'
}
make_derived "$work/clean"
make_derived "$work/conflict"

printf 'upstream\n' > "$upstream/docs/probe.md"
git -C "$upstream" commit -qam 'docs: update probe'
target="$(git -C "$upstream" rev-parse HEAD)"

cd "$work/clean"
tools/upstream apply main >/dev/null
[[ "$(cat docs/probe.md)" == upstream ]]
[[ "$(sed -n 's/^UPSTREAM_REF=//p' .clawfather/upstream.env)" == "$target" ]]
git diff --cached --quiet && { echo 'apply did not stage its changes' >&2; exit 1; }
git commit -qam 'apply update'
echo 'ok: clean apply and base advancement'

cd "$work/conflict"
printf 'derived\n' > docs/probe.md
git commit -qam 'docs: local change'
if tools/upstream apply main >/dev/null 2>&1; then
  echo 'conflicting apply unexpectedly succeeded' >&2; exit 1
fi
[[ -n "$(git ls-files --unmerged)" ]]
[[ "$(sed -n 's/^UPSTREAM_REF=//p' .clawfather/upstream.env)" == "$target" ]]
echo 'ok: conflict is visible and base advances for resolution'

cd "$work/clean"
if tools/upstream apply "$old" >/dev/null 2>&1; then
  echo 'non-descendant target was accepted' >&2; exit 1
fi
[[ "$(sed -n 's/^UPSTREAM_REF=//p' .clawfather/upstream.env)" == "$target" ]]
echo 'ok: non-descendant target rejected without changing base'

sed -i.bak '/^set -euo pipefail$/a\
[[ -z "${CLAW_TEST_MARKER:-}" ]] || printf "ran\\n" > "$CLAW_TEST_MARKER"
' "$upstream/tools/upstream"
rm "$upstream/tools/upstream.bak"
git -C "$upstream" commit -qam 'tools: target tool marker'
CLAW_TEST_MARKER="$work/target-ran" tools/upstream apply main >/dev/null
[[ "$(cat "$work/target-ran")" == ran ]]
echo 'ok: target revision tool executed'
