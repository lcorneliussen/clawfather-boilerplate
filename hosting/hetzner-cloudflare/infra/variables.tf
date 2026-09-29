# Instance and names ---------------------------------------------------------

variable "instance" {
  description = "Instance slug (CLAW_INSTANCE in site/claw.env). Names every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.instance))
    error_message = "instance must be lowercase [a-z0-9-], starting with a letter."
  }
}

variable "zone_name" {
  description = "Cloudflare DNS zone the hostnames live in, e.g. example.com."
  type        = string
}

variable "claw_hostname" {
  description = "Public hostname of the Control UI (CLAW_HOSTNAME). Default: claw.<zone_name>."
  type        = string
  default     = null
}

variable "ssh_hostname" {
  description = "Hostname for SSH through Access (CI deploys and operators). Default: ssh.<zone_name>."
  type        = string
  default     = null
}

# Hetzner --------------------------------------------------------------------

variable "server_name" {
  description = "Hetzner server name. Default: <instance>-1."
  type        = string
  default     = null
}

variable "server_type" {
  description = "Hetzner server type. Arm types (cax*) need CLAW_PLATFORM=linux/arm64 for the image build."
  type        = string
  default     = "cx33"
}

variable "server_location" {
  description = "Hetzner location code; the volume is created in the same location."
  type        = string
  default     = "fsn1"
}

variable "server_image" {
  description = "Hetzner OS image. The Ansible roles target Ubuntu LTS."
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  description = "Public key for initial root access (bootstrap only; Ansible installs the deploy keys)."
  type        = string
}

variable "ssh_source_cidrs" {
  description = "CIDRs allowed to reach port 22 directly: the recovery path, and the bootstrap before the tunnel exists. Empty closes it."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.ssh_source_cidrs, "0.0.0.0/0") && !contains(var.ssh_source_cidrs, "::/0")
    error_message = "World-open SSH is not accepted; list explicit CIDRs or none."
  }
}

variable "volume_size_gb" {
  description = "Persistent data volume size in GiB (mounted at /srv/<instance>)."
  type        = number
  default     = 50
}

# Cloudflare -----------------------------------------------------------------

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (tunnel, Access)."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID of zone_name."
  type        = string
}

variable "claw_access_emails" {
  description = "Identities Access lets in (CLAW_ACCESS_EMAILS). The gateway repeats the same allowlist."
  type        = set(string)

  validation {
    condition     = length(var.claw_access_emails) > 0
    error_message = "At least one e-mail must be allowed into the Control UI."
  }
}

variable "access_session_duration" {
  description = "How long an Access session to the Control UI lasts."
  type        = string
  default     = "8h"
}

variable "access_idp_ids" {
  description = "Existing Access identity provider IDs to offer (any type: Google, Entra ID, OIDC, one-time PIN, …)."
  type        = list(string)
  default     = []
}

variable "github_oauth_client_id" {
  description = "Optional: client ID of a GitHub OAuth app; when set (non-empty), a GitHub IdP is created and offered."
  type        = string
  default     = null
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "Optional: client secret of that GitHub OAuth app."
  type        = string
  default     = null
  sensitive   = true
}

variable "service_token_duration" {
  description = "Lifetime of the CI Access service token. Rotate before it expires."
  type        = string
  default     = "8760h"
}

variable "extra_ingress" {
  description = <<-EOT
    Additional tunnel routes, placed before the catch-all 404. A site
    extension (for example, a wildcard for per-agent portals served by a
    sidecar) adds its hostnames here — plus the DNS records and Access
    applications that cover them.
  EOT
  type = list(object({
    hostname = string
    service  = string
  }))
  default = []
}
