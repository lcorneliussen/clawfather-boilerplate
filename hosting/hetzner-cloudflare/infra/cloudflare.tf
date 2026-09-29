resource "random_bytes" "tunnel_secret" {
  length = 32
}

# A remotely managed tunnel: routes live here, the connector (compose service
# `cloudflared`) only needs the token.
resource "cloudflare_zero_trust_tunnel_cloudflared" "claw" {
  account_id    = var.cloudflare_account_id
  name          = var.instance
  config_src    = "cloudflare"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "claw" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.claw.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "claw" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.claw.id

  config = {
    ingress = concat(
      [
        # The connector sits on the claw compose network, so the gateway is
        # reached by service name — no host port involved.
        {
          hostname = local.claw_hostname
          service  = "http://claw:18789"
        },
        # sshd runs on the host, outside compose; host.docker.internal maps to
        # the bridge gateway (extra_hosts in compose.yml).
        {
          hostname = local.ssh_hostname
          service  = "ssh://host.docker.internal:22"
        },
      ],
      var.extra_ingress,
      [
        {
          service = "http_status:404"
        },
      ],
    )
  }
}

resource "cloudflare_dns_record" "claw" {
  zone_id = var.cloudflare_zone_id
  name    = local.claw_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.claw.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "${var.instance}: Control UI via tunnel (OpenTofu)"
}

resource "cloudflare_dns_record" "ssh" {
  zone_id = var.cloudflare_zone_id
  name    = local.ssh_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.claw.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "${var.instance}: SSH via tunnel (OpenTofu)"
}
