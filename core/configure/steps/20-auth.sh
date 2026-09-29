# shellcheck shell=sh
# Who may speak to the gateway. The profile chooses the mode in its
# profile.env; the instance supplies the people in instance/claw.env. Upstream-owned.
#
#   token          a shared bearer token (OPENCLAW_GATEWAY_TOKEN). Local only.
#   trusted-proxy  a front door authenticates people and forwards their
#                  identity in a header; the gateway trusts exactly one
#                  proxy address (the profile pins it on the claw network).

case "${CLAW_AUTH_MODE:?set by hosting/<profile>/profile.env}" in
  token)
    : "${OPENCLAW_GATEWAY_TOKEN:?token auth needs OPENCLAW_GATEWAY_TOKEN in .secrets/claw.env}"
    unset_key gateway.trustedProxies
    unset_key gateway.auth.trustedProxy
    set_str gateway.auth.mode token
    ;;

  trusted-proxy)
    : "${CLAW_TRUSTED_PROXY:?}" "${CLAW_IDENTITY_HEADER:?}" "${CLAW_REQUIRED_HEADER:?}"
    require_json_array CLAW_ADMIN_EMAILS

    # Only the pinned proxy may speak for a user; anything else — including
    # loopback — is rejected before identity headers are read.
    set_json gateway.trustedProxies "$(json '[a[0]]' "$CLAW_TRUSTED_PROXY")"
    set_str gateway.auth.trustedProxy.userHeader "$CLAW_IDENTITY_HEADER"
    # A second header the proxy always sets, so a response without identity
    # can never pass as anonymous.
    set_json gateway.auth.trustedProxy.requiredHeaders "$(json '[a[0]]' "$CLAW_REQUIRED_HEADER")"

    # Where authorization is decided. A front door that can express "anyone
    # at this domain" decides alone (CLAW_GATEWAY_ALLOWLIST=no); otherwise
    # the gateway repeats the allowlist as a second fence.
    if [ "${CLAW_GATEWAY_ALLOWLIST:-yes}" = yes ]; then
      require_json_array CLAW_ACCESS_EMAILS
      set_json gateway.auth.trustedProxy.allowUsers \
        "$(json 'j(a[0]).map(e => e.toLowerCase())' "$CLAW_ACCESS_EMAILS")"
    else
      unset_key gateway.auth.trustedProxy.allowUsers
    fi

    # Everyone the front door admits becomes an operator on their first
    # device; admins additionally get operator.admin.
    set_json gateway.auth.trustedProxy.deviceAutoApprove \
      '{"enabled":true,"scopes":["operator.read","operator.write","operator.approvals","operator.questions"]}'
    set_json gateway.auth.identityScopes \
      "$(json 'Object.fromEntries(j(a[0]).map(e => [e.toLowerCase(), ["operator.admin"]]))' "$CLAW_ADMIN_EMAILS")"
    set_str gateway.auth.mode trusted-proxy
    ;;

  *)
    log "unknown CLAW_AUTH_MODE: $CLAW_AUTH_MODE"; exit 1 ;;
esac
