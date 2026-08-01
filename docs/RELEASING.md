# Marketplace release guide

This document covers artifact mechanics. `PUBLISHING.md` is the authoritative
provider enrollment, submission, listing, and final release-gate runbook.

## Release invariants

Before starting a marketplace review:

1. Update and test the image tags in `versions.env` and the defaults in the
   canonical Compose file.
2. Run `make sync && make validate`.
3. Test each artifact on a clean supported instance with at least 2 GB RAM.
4. Confirm DNS, trusted TLS, dashboard, OIDC discovery, API authentication,
   STUN port exposure, reboot persistence, and SSH access.
5. Tag the repository and update the default `ONECLICKS_REF` in marketplace
   artifacts to that immutable tag. During development, override it with
   `ONECLICKS_REF=main`; do not publish an adapter that installs from a moving
   branch.

The default repository URL is `https://github.com/netbirdio/one-clicks.git`.
Change `ONECLICKS_REPOSITORY` in the marketplace artifacts if the final
repository is published elsewhere.

## Akamai Cloud / Linode

`marketplaces/linode/stackscript.sh` is the standalone release-tag adapter.
For Akamai's official repository layout, run
`scripts/package-linode-submission.sh` and submit the generated app and
deployment-script directories. Configure the same UDF fields and list only
Ubuntu 24.04 LTS as the supported image. The app requires at least 2 GB RAM.

The account needs at least one active Linode for DNS Manager to serve its
zones. On an otherwise empty account, expect authoritative DNS to become
available after the marketplace instance starts; the installer deliberately
waits for both public resolvers before continuing.

## DigitalOcean

DigitalOcean accepts a prebuilt Droplet image. Build
`marketplaces/digitalocean/packer.pkr.hcl`, run DigitalOcean's official cleanup
and image-check scripts, test the resulting snapshot, and submit its snapshot
ID through the Vendor Portal.

The image deliberately defers instance-specific configuration to the first
root SSH login. The build and runtime DNS tokens are separate credentials.

## Vultr

Create the Marketplace variables described in
`marketplaces/vultr/README.md`, then use `vendor-data.yml` as cloud-init
vendor-data. Vultr app-variable names must remain 15 characters or fewer.
Build from a cloud-init-capable Ubuntu image using Vultr's small marketplace
build plan, then run Vultr's image checks before creating a live build.

## Hostinger

Run `make sync`, publish the repository, and use the raw URL for
`marketplaces/hostinger/docker-compose.yml` as the `compose_url` in the Deploy
on Hostinger button. Test the environment-variable form and document the
required hPanel firewall rules.

## Hetzner Cloud

Build `marketplaces/hetzner/packer.pkr.hcl` with a temporary Hetzner API token.
Test the resulting snapshot ID from `build/hetzner-manifest.json` on the
minimum supported plan, using both generated cloud-init data and the first-root
login fallback. Confirm that the Packer build server is gone and delete test
servers, unused snapshots, Primary IPs, and temporary SSH keys after testing.

DNS must be updated outside the instance before the shared propagation gate
finishes. If a Hetzner Cloud Firewall is attached, account for its stateless
UDP behavior in addition to opening the documented application ports.

Hetzner's public Apps repository currently does not accept new applications.
Treat the snapshot as a private artifact unless a direct provider review has
been agreed.
