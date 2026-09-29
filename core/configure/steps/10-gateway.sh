# shellcheck shell=sh
# Gateway basics every profile shares. Upstream-owned.

# Chromium inside the container has no user namespaces; the upstream browser
# image expects this.
set_json browser.noSandbox 'true'

# The Control UI is served from the public hostname and, for operations, from
# host loopback.
set_json gateway.controlUi.allowedOrigins "$(json '[
  ...(a[0] ? ["https://" + a[0]] : []),
  "http://localhost:" + a[1], "http://127.0.0.1:" + a[1]]' "${CLAW_HOSTNAME:-}" "${CLAW_PORT:-18789}")"
