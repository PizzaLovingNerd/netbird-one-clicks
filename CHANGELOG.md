# Changelog

All notable changes to NetBird One-Click Marketplaces are documented here.

## 0.1.0 - 2026-08-01

Initial marketplace release.

### Added

- Shared NetBird installation through shell and Ansible entry points.
- Akamai Cloud / Linode StackScript and official submission-tree export.
- DigitalOcean and Hetzner Packer snapshot build definitions with guarded
  first-login setup.
- Vultr cloud-init Vendor Data and a Hostinger Docker Compose deployment.
- Provider-neutral validation and opt-in live deployment tests.

### Runtime components

- NetBird Server 0.76.0
- NetBird Dashboard 2.90.8
- Traefik 3.7.10
- Alpine Linux 3.22.5

All runtime images are pinned to release tags and must be rebuilt and retested
whenever a pin changes, as described in `docs/COMPONENTS.md` and `UPDATING.md`.
