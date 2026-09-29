# Which identity providers Access offers. Nothing configured: allowed_idps
# stays unset and every login method of the account is offered.
locals {
  # An unset CI secret arrives as "", not null. Whether the IdP exists is not
  # itself secret, and count cannot depend on a sensitive value.
  github_idp = nonsensitive(var.github_oauth_client_id != null && var.github_oauth_client_id != "")
}

resource "cloudflare_zero_trust_access_identity_provider" "github" {
  count      = local.github_idp ? 1 : 0
  account_id = var.cloudflare_account_id
  name       = "GitHub (${var.instance})"
  type       = "github"

  config = {
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
  }
}

locals {
  idp_ids = concat(
    var.access_idp_ids,
    cloudflare_zero_trust_access_identity_provider.github[*].id,
  )
  allowed_idps = length(local.idp_ids) > 0 ? local.idp_ids : null

  # The same allowlist the gateway repeats (CLAW_ACCESS_EMAILS).
  people = [for email in var.claw_access_emails : { email = { email = email } }]
}

# CI's identity for SSH through Access (deploy workflow). Its client id and
# secret go to the deploy environment's secrets.
resource "cloudflare_zero_trust_access_service_token" "ci" {
  account_id = var.cloudflare_account_id
  name       = "${var.instance} CI"
  duration   = var.service_token_duration
}

resource "cloudflare_zero_trust_access_application" "claw" {
  account_id                 = var.cloudflare_account_id
  name                       = var.instance
  domain                     = local.claw_hostname
  type                       = "self_hosted"
  session_duration           = var.access_session_duration
  app_launcher_visible       = true
  allowed_idps               = local.allowed_idps
  auto_redirect_to_identity  = length(local.idp_ids) == 1
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"

  # People only. No service token here: the gateway authenticates by the
  # e-mail header, which a service token does not carry.
  policies = [
    {
      name       = "${var.instance} people"
      decision   = "allow"
      precedence = 1
      include    = local.people
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "ssh" {
  account_id                = var.cloudflare_account_id
  name                      = "${var.instance} SSH"
  domain                    = local.ssh_hostname
  type                      = "self_hosted"
  session_duration          = "1h"
  app_launcher_visible      = false
  allowed_idps              = local.allowed_idps
  service_auth_401_redirect = true

  policies = [
    {
      name       = "${var.instance} CI service token"
      decision   = "non_identity"
      precedence = 1
      include = [
        {
          service_token = {
            token_id = cloudflare_zero_trust_access_service_token.ci.id
          }
        },
      ]
    },
    {
      # Operators: `cloudflared access ssh` in their ssh config; the host
      # still requires their key (Ansible deploy_authorized_keys).
      name       = "${var.instance} operators"
      decision   = "allow"
      precedence = 2
      include    = local.people
    },
  ]
}
