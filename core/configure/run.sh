#!/bin/sh
# Build the next gateway configuration as a candidate beside the live file,
# run every configure step against it, validate it, and leave it at
# $CLAW_CANDIDATE for `bin/claw` to publish while the gateway is stopped.
# The running gateway never observes an intermediate state.
#
# Runs INSIDE the claw image (`bin/claw configure`). Steps run in name order:
# all of core/configure/steps/*.sh, then all of instance/configure.d/*.sh — so an
# instance step can override anything a core step set.
#
# Upstream-owned.
set -eu

state=/home/node/.openclaw
live="$state/openclaw.json"
CLAW_CANDIDATE="$state/openclaw.candidate.json"

staged="$(mktemp "$state/.openclaw.json.XXXXXX")"
trap 'rm -f "$staged"' EXIT
if [ -f "$live" ]; then cat "$live" > "$staged"; else printf '{}\n' > "$staged"; fi
chmod 0600 "$staged"
export OPENCLAW_CONFIG_PATH="$staged"

# shellcheck source=core/configure/lib.sh
. /claw/core/configure/lib.sh

for step in /claw/core/configure/steps/*.sh /claw/instance/configure.d/*.sh; do
  [ -f "$step" ] || continue
  log "${step#/claw/}"
  # shellcheck disable=SC1090
  . "$step"
done

openclaw config validate --json | node -e '
  let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
    const r = JSON.parse(s); if (r.valid !== true) { console.error(s); process.exit(1) } })'

mv -f "$staged" "$CLAW_CANDIDATE"
trap - EXIT
log "candidate ready: ${CLAW_CANDIDATE#"$state"/}"
