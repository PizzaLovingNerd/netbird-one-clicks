packer {
  required_plugins {
    hcloud = {
      source  = "github.com/hetznercloud/hcloud"
      version = ">= 1.7.2, < 2.0.0"
    }
  }
}

variable "hcloud_token" {
  type      = string
  default   = env("HCLOUD_TOKEN")
  sensitive = true
}

variable "base_image" {
  type        = string
  default     = "ubuntu-24.04"
  description = "Supported Hetzner Ubuntu image used to build the snapshot."

  validation {
    condition     = contains(["ubuntu-24.04", "ubuntu-26.04"], var.base_image)
    error_message = "Base image must be ubuntu-24.04 or ubuntu-26.04."
  }
}

variable "location" {
  type    = string
  default = "fsn1"
}

variable "server_type" {
  type        = string
  default     = "cx23"
  description = "Temporary build server; the published app requires at least 2 GB RAM."
}

variable "snapshot_name" {
  type    = string
  default = "netbird-one-click-0.76.0-ubuntu-24.04-{{timestamp}}"
}

source "hcloud" "netbird" {
  token                = var.hcloud_token
  image                = var.base_image
  location             = var.location
  server_type          = var.server_type
  server_name          = "netbird-one-click-packer-{{timestamp}}"
  ssh_timeout          = "10m"
  ssh_username         = "root"
  public_ipv6_disabled = true
  snapshot_name        = var.snapshot_name

  server_labels = {
    application = "netbird"
    purpose     = "image-build"
  }

  snapshot_labels = {
    application = "netbird"
    managed-by  = "packer"
    one-click   = "true"
  }
}

build {
  name    = "netbird-hetzner"
  sources = ["source.hcloud.netbird"]

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
    script = "marketplaces/hetzner/install-image.sh"
  }

  provisioner "shell" {
    script = "marketplaces/hetzner/cleanup-image.sh"
  }

  post-processor "manifest" {
    output     = "build/hetzner-manifest.json"
    strip_path = true
  }
}
