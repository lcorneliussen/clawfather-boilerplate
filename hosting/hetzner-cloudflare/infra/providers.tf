# Credentials come from the environment only:
#   HCLOUD_TOKEN          Hetzner Cloud project API token (read/write)
#   CLOUDFLARE_API_TOKEN  Cloudflare token with Zone DNS edit, Zero Trust edit
#                         and Cloudflare Tunnel edit on the account
provider "hcloud" {}

provider "cloudflare" {}
