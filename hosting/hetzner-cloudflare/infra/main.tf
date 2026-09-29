# Profile infrastructure: one Hetzner host with a persistent volume, and the
# Cloudflare side that makes it reachable — tunnel, DNS, Access. Upstream-owned.
#
#   hetzner.tf     server, volume, firewall, bootstrap SSH key
#   cloudflare.tf  tunnel, its remotely managed routes, DNS records
#   access.tf      identity providers, Access applications, CI service token
locals {
  server_name   = coalesce(var.server_name, "${var.instance}-1")
  claw_hostname = coalesce(var.claw_hostname, "claw.${var.zone_name}")
  ssh_hostname  = coalesce(var.ssh_hostname, "ssh.${var.zone_name}")

  labels = {
    instance   = var.instance
    managed_by = "opentofu"
  }
}
