# DigitalOcean Vendor Portal data

- Listing type: Droplet 1-Click App
- Name: NetBird Self-Hosted
- Version: 0.1.0
- Operating system: Ubuntu 26.04 LTS
- Minimum Droplet: 2 GB RAM
- Category: Security
- Support URL: https://docs.netbird.io/help/netbird-support
- Support email: support@netbird.io
- Image ID: replace with the final Packer snapshot ID from `build/manifest.json`

## Summary

Deploy a self-hosted NetBird control plane with an administration dashboard,
embedded identity provider, relay, automatic HTTPS, and hardened host defaults.

## Description

NetBird is an open-source network security platform that creates secure,
WireGuard-based private networks between devices, servers, and infrastructure.
This image preinstalls the supported host dependencies and starts an
interactive, guarded setup on the first root SSH login. The setup collects a
public hostname and certificate email, creates a limited sudo administrator,
configures UFW and Fail2ban, starts the pinned NetBird containers, and verifies
trusted HTTPS and API authentication. Users can optionally configure a
DigitalOcean DNS A record through a scoped token, or point DNS to the Droplet
before setup. Persistent Docker volumes retain configuration, data, and
certificate state across restarts and reboots.

## Software included

Copy the component name, version, license, and website fields from
`docs/COMPONENTS.md`. For the image itself, include Ubuntu 26.04 LTS, Docker
Engine and Compose, Ansible 14.0.0, NetBird Server 0.76.0, NetBird Dashboard
2.90.8, Traefik 3.7.10, and Alpine 3.22.5.

## First-use instructions

1. Create a Droplet with an account SSH key and at least 2 GB RAM.
2. Point the intended hostname to the new public IPv4 address.
3. Log in as root over SSH and complete the guarded first-login prompts.
4. Confirm limited-user SSH works before closing the root session.
5. Open the HTTPS dashboard and create the first NetBird administrator.

The final snapshot must show 0 failures and 0 warnings from DigitalOcean's
official checker. Attach that log and the release-specific live-test report to
the Vendor Portal submission.
