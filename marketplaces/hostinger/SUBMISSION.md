# Hostinger publication data

Hostinger's public one-click mechanism is a self-published **Deploy on
Hostinger** button. Its public documentation does not provide a third-party
Docker Catalog submission form.

## Deploy button

After publishing release `v0.1.0`, URL-encode this immutable Compose URL:

```text
https://raw.githubusercontent.com/netbirdio/one-clicks/v0.1.0/marketplaces/hostinger/docker-compose.yml
```

Use it in the official button:

```markdown
[![Deploy on Hostinger](https://assets.hostinger.com/vps/deploy.svg)](https://www.hostinger.com/docker-hosting?compose_url=ENCODED_RAW_COMPOSE_URL)
```

## Listing copy

NetBird is an open-source network security platform that creates secure,
WireGuard-based private networks between devices, servers, and infrastructure.
This Compose deployment runs a self-hosted NetBird control plane with its
dashboard, embedded identity provider, relay, and automatic HTTPS. Persistent
volumes retain configuration, application data, and certificate state across
restarts.

## Customer inputs

- `NETBIRD_FQDN`: required public hostname already resolving to the VPS.
- `NETBIRD_ACME_EMAIL`: required Let's Encrypt account email.

The customer must allow inbound TCP 80 and 443 and UDP 3478 in hPanel. SSH and
host hardening remain owned by the Hostinger Docker VPS template.

## Curated Docker Catalog

The catalog has no documented public vendor-submission procedure. Contact the
Hostinger partnership/product team with the release URL, this listing copy,
the live-test report, the approved NetBird icon, screenshots, and the support
contact. Treat catalog inclusion as provider-dependent; the Deploy button can
be published without waiting for catalog approval.
