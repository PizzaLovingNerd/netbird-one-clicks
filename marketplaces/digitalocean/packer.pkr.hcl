packer {
  required_plugins {
    digitalocean = {
      source  = "github.com/digitalocean/digitalocean"
      version = ">= 1.4.0, < 2.0.0"
    }
  }
}

variable "do_api_token" {
  type      = string
  default   = env("DIGITALOCEAN_TOKEN")
  sensitive = true
}

variable "base_image" {
  type        = string
  default     = "ubuntu-26-04-x64"
  description = "Use ubuntu-24-04-x64 as the supported fallback."

  validation {
    condition     = contains(["ubuntu-26-04-x64", "ubuntu-24-04-x64"], var.base_image)
    error_message = "Base image must be ubuntu-26-04-x64 or ubuntu-24-04-x64."
  }
}

variable "region" {
  type    = string
  default = "nyc3"
}

variable "size" {
  type        = string
  default     = "s-1vcpu-2gb"
  description = "The published app requires at least 2 GB RAM."
}

variable "snapshot_name" {
  type    = string
  default = "netbird-one-click-0.76.0-ubuntu-26-04-{{timestamp}}"
}

variable "manifest_output" {
  type        = string
  default     = "build/manifest.json"
  description = "Path for Packer's machine-readable build manifest."
}

source "digitalocean" "netbird" {
  api_token          = var.do_api_token
  droplet_agent      = false
  image              = var.base_image
  ipv6               = false
  monitoring         = false
  private_networking = false
  region             = var.region
  size               = var.size
  snapshot_name      = var.snapshot_name
  ssh_timeout        = "10m"
  ssh_username       = "root"
  tags               = ["marketplace", "netbird", "one-click"]
}

build {
  name    = "netbird-digitalocean"
  sources = ["source.digitalocean.netbird"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "install -d -m 0700 /tmp/netbird-source",
    ]
  }

  provisioner "file" {
    sources = [
      "ansible",
      "marketplaces",
      "shared",
      "getting-started.sh",
      "getting-started.yml",
      "requirements.txt",
      "versions.env",
      "VERSION",
    ]
    destination = "/tmp/netbird-source/"
  }

  provisioner "shell" {
    script = "marketplaces/digitalocean/install-image.sh"
  }

  provisioner "shell" {
    script = "marketplaces/digitalocean/run-official-cleanup.sh"
  }

  provisioner "shell" {
    script = "marketplaces/digitalocean/run-official-image-check.sh"
  }

  post-processor "manifest" {
    output     = var.manifest_output
    strip_path = true
  }
}
