# shellcheck shell=sh
# Helpers for configure steps. Sourced by core/configure/run.sh INSIDE the
# claw image, so a step sees the gateway's exact env and mounts. Every write
# goes to the candidate config ($OPENCLAW_CONFIG_PATH), never the live one.
#
# Upstream-owned. Site steps (site/configure.d/*.sh) use the same helpers.

openclaw() { node dist/index.js "$@"; }

# set_json KEY JSON — set a key to a JSON value (object, array, bool, number).
set_json() { openclaw config set "$1" "$2" --strict-json >/dev/null; }

# set_str KEY STRING — set a key to a plain string.
set_str() { openclaw config set "$1" "$2" >/dev/null; }

# unset_key KEY — remove a key; absent keys are fine.
unset_key() { openclaw config unset "$1" >/dev/null 2>&1 || true; }

# has_key KEY — true when the key exists in the candidate.
has_key() { openclaw config get "$1" >/dev/null 2>&1; }

# json EXPR [ARG...] — evaluate a JS expression over args and print JSON.
# `a` is the argv array; `j(s)` parses JSON. Example:
#   json 'j(a[0]).map(e => e.toLowerCase())' "$CLAW_ADMIN_EMAILS"
json() {
  expr="$1"; shift
  node -e 'const a = process.argv.slice(1); const j = JSON.parse;
    process.stdout.write(JSON.stringify(('"$expr"')))' -- "$@"
}

# require_json_array NAME — fail unless $NAME holds a JSON array of non-empty strings.
require_json_array() {
  eval "value=\${$1:-}"
  # shellcheck disable=SC2154 # assigned by the eval above
  node -e 'const v = JSON.parse(process.argv[1]);
    if (!Array.isArray(v) || !v.every(s => typeof s === "string" && s.length))
      process.exit(1)' -- "$value" 2>/dev/null ||
    { echo "configure: $1 must be a JSON array of non-empty strings" >&2; exit 1; }
}

log() { echo "configure: $*" >&2; }
