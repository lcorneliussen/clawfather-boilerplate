output "server_ipv4" {
  description = "Public IPv4 — bootstrap and recovery SSH only (ansible_host)."
  value       = hcloud_server.host.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 — bootstrap and recovery SSH only."
  value       = hcloud_server.host.ipv6_address
}

output "volume_linux_device" {
  description = "Pass to Ansible as claw_volume_device."
  value       = hcloud_volume.data.linux_device
}

output "claw_hostname" {
  description = "Set as CLAW_HOSTNAME in instance/claw.env."
  value       = local.claw_hostname
}

output "ssh_hostname" {
  description = "Set as the CLAW_SSH_HOSTNAME repository variable."
  value       = local.ssh_hostname
}

output "cloudflare_tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.claw.id
}

output "cloudflare_tunnel_token" {
  description = "Connector token; store as the CLOUDFLARE_TUNNEL_TOKEN deploy secret."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.claw.token
  sensitive   = true
}

output "ci_access_client_id" {
  description = "Access service-token client ID; store as the CF_ACCESS_CLIENT_ID deploy secret."
  value       = cloudflare_zero_trust_access_service_token.ci.client_id
  sensitive   = true
}

output "ci_access_client_secret" {
  description = "Access service-token secret; store as the CF_ACCESS_CLIENT_SECRET deploy secret."
  value       = cloudflare_zero_trust_access_service_token.ci.client_secret
  sensitive   = true
}
