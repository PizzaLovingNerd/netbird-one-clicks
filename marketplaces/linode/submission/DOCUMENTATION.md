---
title: "Deploy NetBird through the Akamai Cloud Marketplace"
description: "Deploy a self-hosted NetBird control plane on Ubuntu 24.04 LTS."
published: 2026-07-31
keywords: [netbird, wireguard, zero-trust, vpn, self-hosted]
tags: [security, networking, marketplace]
external_resources:
  - https://docs.netbird.io/
---

# Deploy NetBird through the Akamai Cloud Marketplace

NetBird creates secure WireGuard-based private networks between devices,
servers, and infrastructure. The Marketplace deployment installs the NetBird
combined server, dashboard, embedded identity provider, relay, Docker, and a
Traefik HTTPS endpoint on one Compute Instance.

## Before you begin

- Distribution: Ubuntu 24.04 LTS only.
- Suggested plan: Shared CPU 2 GB (`g6-standard-1`) or larger.
- Select an account SSH key during deployment.
- Prepare a public DNS zone and hostname for the service.
- Allow TCP 80 and 443 and UDP 3478 to reach the instance. The deployment
  configures the host firewall automatically.

## Configuration fields

| Field | Required | Description |
| --- | --- | --- |
| Existing DNS zone | Yes | Zone such as `example.com` |
| NetBird subdomain | Yes | Label such as `netbird`, or `@` for the apex |
| Let's Encrypt email | Yes | Address used for certificate notices |
| Linode DNS API token | No | Scoped Domains read/write token for automatic A-record setup |
| Limited sudo username | Yes | Linux administrator created by the deployment |
| Disable root SSH | Yes | Copies the provider key to the limited user before disabling root login |

If no DNS API token is supplied, create the A record after the instance IP is
known. Provisioning waits for both `1.1.1.1` and `8.8.8.8` to return exactly
that IP before requesting a certificate.

## Access NetBird

When provisioning completes, open `https://<your-hostname>/` and create the
first NetBird administrator in the browser wizard. SSH to the limited user
with the key selected during deployment.

The generated sudo password and operational commands are stored at:

```text
/home/<admin-user>/.credentials
```

The file is owned by the limited user and has mode `0600`. Deployment logs are
available at `/var/log/stackscript.log` and
`/var/log/netbird-one-click.log`.

## Operate the deployment

```bash
cd /opt/netbird
sudo docker compose ps
sudo docker compose logs
```

Persistent data is stored in the `netbird_data`, `netbird_config`, and
`netbird_traefik_letsencrypt` Docker volumes. Back up those volumes before
replacing the server.

## Screenshots

Attach current, redacted screenshots of the first-administrator login flow and
the peer dashboard from the release-candidate deployment to the Marketplace
submission. Do not use screenshots containing customer names, email addresses,
IP addresses, tokens, or credentials.

## Support

See [NetBird Support](https://docs.netbird.io/help/netbird-support) for
community and commercial support paths.
