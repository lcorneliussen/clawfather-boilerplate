#!/usr/bin/env bash
# Run by a host-side systemd unit after the workflow has saved the prior repo.
# The unit survives a lost SSH connection, so rollback can finish on the host.
set -euo pipefail

: "${CLAW_ROLLBACK_DIR:?}"
cd "$(dirname "$0")/../.."
root="$PWD"
data="$(bin/claw env | sed -n 's/^CLAW_DATA=//p')"
allowlist="$data/oauth2-proxy/emails.txt"
had_allowlist=false
[[ ! -f "$allowlist" ]] || had_allowlist=true
if $had_allowlist; then sudo cp -p "$allowlist" "$CLAW_ROLLBACK_DIR/emails.txt"; fi

rollback() {
  local status=$?
  ((status)) || return 0
  sudo rm -f "$allowlist.next"
  if [[ -d "$CLAW_ROLLBACK_DIR/repo" ]]; then
    echo 'claw: restoring the previous repository and proxy configuration' >&2
    rsync -a --delete --exclude=/.data --exclude=/.secrets --exclude=/.git --exclude=/.rollback \
      "$CLAW_ROLLBACK_DIR/repo/" "$root/"
    if [[ -f "$CLAW_ROLLBACK_DIR/claw.env" ]]; then
      install -m 0600 "$CLAW_ROLLBACK_DIR/claw.env" "$root/.secrets/claw.env"
    fi
    if $had_allowlist; then
      sudo cp -p "$CLAW_ROLLBACK_DIR/emails.txt" "$allowlist"
    else
      sudo rm -f "$allowlist"
    fi
    unset CLAW_IMAGE CLAW_BUILD
    bin/claw compose up -d --remove-orphans || true
    bin/claw compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
    bin/claw health 30 || true
  fi
  echo "claw: rollout failed with status $status" >&2
}
trap rollback EXIT

emails="$(set -a; . hosting/azure/profile.env; . instance/claw.env; printf '%s' "$CLAW_ACCESS_EMAILS")"
sudo install -d -o 1000 -g 1000 -m 0750 "$data/oauth2-proxy"
jq -r '.[] | ascii_downcase' <<<"$emails" \
  | sudo install -o 1000 -g 1000 -m 0640 /dev/stdin "$allowlist.next"
[[ -f "$allowlist" ]] || sudo cp -p "$allowlist.next" "$allowlist"

docker pull --quiet "$CLAW_IMAGE"
bin/claw deploy
sudo mv -f "$allowlist.next" "$allowlist"
bin/claw compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
rm -rf "$CLAW_ROLLBACK_DIR"
trap - EXIT
