# DigitalOcean adapter

DigitalOcean Droplet 1-Click Apps are prebuilt images. This adapter packages
the unified repository into a Packer snapshot, preinstalls Docker and Ansible,
and defers the hostname and certificate inputs to the first root SSH login.

Build from the repository root:

```bash
export DIGITALOCEAN_TOKEN='temporary-build-token'
mkdir -p build
packer init marketplaces/digitalocean/packer.pkr.hcl
packer build marketplaces/digitalocean/packer.pkr.hcl
```

The build runs DigitalOcean's official cleanup and image-check scripts from a
pinned upstream commit and verifies their SHA-256 checksums. The resulting
snapshot ID is written to `build/manifest.json`.

The user should create the Droplet with an account SSH key and at least 2 GB
RAM. On first login the shared installer prompts for the FQDN, Let's Encrypt
email, limited user, and optional DigitalOcean DNS token. Runtime DNS
automation needs access to read and create/update records in the selected
zone. The runtime token is unrelated to the temporary Packer build token.
