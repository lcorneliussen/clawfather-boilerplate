resource "hcloud_ssh_key" "bootstrap" {
  name       = "${var.instance}-bootstrap"
  public_key = var.ssh_public_key
  labels     = local.labels
}

# Nothing is published: the tunnel dials out, so the only inbound port is a
# restricted SSH recovery path (and none at all when ssh_source_cidrs is empty).
resource "hcloud_firewall" "host" {
  name   = var.instance
  labels = local.labels

  dynamic "rule" {
    for_each = length(var.ssh_source_cidrs) > 0 ? [1] : []
    content {
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = var.ssh_source_cidrs
      description = "Restricted recovery SSH"
    }
  }

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Path MTU discovery and diagnostics"
  }
}

resource "hcloud_server" "host" {
  name               = local.server_name
  server_type        = var.server_type
  location           = var.server_location
  image              = var.server_image
  ssh_keys           = [hcloud_ssh_key.bootstrap.id]
  firewall_ids       = [hcloud_firewall.host.id]
  delete_protection  = true
  rebuild_protection = true
  labels             = local.labels

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    prevent_destroy = true
    # Both only matter at first boot and would otherwise force a replacement
    # (blocked by prevent_destroy) when the bootstrap key rotates or the
    # image default moves. The host is maintained by Ansible from then on.
    ignore_changes = [image, ssh_keys]
  }
}

# All gateway state lives here (mounted at /srv/<instance> by Ansible), so the
# server can be rebuilt without touching it.
resource "hcloud_volume" "data" {
  name              = "${var.instance}-data"
  size              = var.volume_size_gb
  location          = var.server_location
  format            = "ext4"
  delete_protection = true
  labels            = local.labels

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.host.id
  # Ansible owns the mount (path, options), not cloud-init.
  automount = false
}
