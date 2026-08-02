# NetBird One-Click Marketplaces

This repository provides one NetBird deployment implementation with native
adapters for Akamai Cloud (Linode), DigitalOcean, Vultr, Hostinger, and
Hetzner Cloud.

The shared deployment is a single-node NetBird control plane using the combined
NetBird server, embedded identity provider, dashboard, and Traefik with
automatic Let's Encrypt TLS. Marketplace entry points do not fork the
application configuration:

| Target | Native artifact | Shared implementation |
| --- | --- | --- |
| Akamai Cloud / Linode | StackScript + Ansible | `getting-started.sh` and `getting-started.yml` |
| DigitalOcean | Packer-built Droplet snapshot | Bundled repository + first-login setup |
| Vultr | cloud-init vendor-data | `getting-started.sh` and `getting-started.yml` |
| Hostinger | Docker Compose URL | Generated copy of `shared/docker-compose.yml` |
| Hetzner Cloud | Packer-built snapshot | Bundled repository + cloud-init or first-login setup |
| Generic server | Shell or Ansible | `getting-started.sh` or `getting-started.yml` |

## Repository layout

```text
ansible/                  Shared host installation and provider hooks
shared/                   Canonical Docker Compose application model
marketplaces/linode/      StackScript and Marketplace metadata
marketplaces/digitalocean Packer snapshot and first-login adapter
marketplaces/vultr/       cloud-init vendor-data and variable contract
marketplaces/hostinger/   Compose URL artifact and Deploy button
marketplaces/hetzner/      Packer snapshot and first-boot adapter
scripts/                  Asset synchronization and validation
getting-started.sh        Generic/provider bootstrap
getting-started.yml       Stable Ansible playbook entry point
```

See [Architecture and marketplace fit](docs/ARCHITECTURE.md) for the shared
source model, extension contract, and provider-guideline analysis. See the
[Marketplace release guide](docs/RELEASING.md) for provider-specific
release mechanics. Use [PUBLISHING.md](PUBLISHING.md) as the authoritative
submission checklist and provider-portal runbook. See [TESTS.md](TESTS.md) for
the disabled-by-default GitHub Actions live tests. Use
[UPDATING.md](UPDATING.md) whenever NetBird's upstream quick-start changes.

The adapter code is BSD-3-Clause licensed. Runtime components and their
separate licenses are listed in [docs/COMPONENTS.md](docs/COMPONENTS.md).

## Generic installation

The hostname must already resolve to the server unless a supported DNS API
token is provided.

```bash
sudo ./getting-started.sh \
  --domain netbird.example.com \
  --email admin@example.com
```

For automation, use environment variables:

```bash
sudo \
  NETBIRD_FQDN=netbird.example.com \
  NETBIRD_ACME_EMAIL=admin@example.com \
  ./getting-started.sh --non-interactive
```

Supported common inputs are documented in
[`ansible/group_vars/all.yml`](ansible/group_vars/all.yml).

## Development

```bash
make sync
make validate
```

`make validate` checks shell and YAML syntax, validates the Ansible model when
Ansible is installed, and fails if the generated Hostinger Compose artifact
has drifted from the canonical shared model.

## Release artifacts

From a clean release commit, build all static submission and image-build
packages with:

```bash
make artifacts
```

The versioned directory under `build/releases/` contains deterministic source,
generic installer, Akamai/Linode, DigitalOcean, Vultr, Hostinger, and Hetzner
archives, plus `SHA256SUMS` and a machine-readable release manifest. The
DigitalOcean and Hetzner archives are complete Packer build contexts; provider
API tokens are intentionally required later to create the cloud snapshots.
