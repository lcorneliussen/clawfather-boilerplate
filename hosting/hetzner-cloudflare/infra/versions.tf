# Upstream-owned. Provider versions are pinned here and locked in
# .terraform.lock.hcl; bump both by PR.
terraform {
  required_version = ">= 1.12.0, < 2.0.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.24"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.68"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Remote state in any S3-compatible bucket (Cloudflare R2 works well):
  #   tofu init -backend-config=<repo>/site/infra/backend.hcl
  # The site's backend.hcl holds no credentials; AWS_ACCESS_KEY_ID and
  # AWS_SECRET_ACCESS_KEY come from the environment. See backend.hcl.example.
  backend "s3" {}
}
