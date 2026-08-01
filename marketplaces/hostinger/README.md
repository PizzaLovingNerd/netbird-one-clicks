# Hostinger adapter

Hostinger's Docker Manager consumes a public Compose URL. Publish this
repository, then use:

```text
https://raw.githubusercontent.com/netbirdio/one-clicks/<release>/marketplaces/hostinger/docker-compose.yml
```

as the `compose_url` in Hostinger's official Deploy button:

```markdown
[![Deploy on Hostinger](https://assets.hostinger.com/vps/deploy.svg)](https://www.hostinger.com/docker-hosting?compose_url=RAW_COMPOSE_URL)
```

Set these environment variables in Docker Manager before deployment:

- `NETBIRD_FQDN`: a public hostname that already resolves to the VPS.
- `NETBIRD_ACME_EMAIL`: the Let's Encrypt account email.

Allow inbound 80/tcp, 443/tcp, and 3478/udp in the Hostinger firewall. SSH is
managed by the Hostinger VPS template and is intentionally outside this
Compose-only adapter.

This file is generated from `shared/docker-compose.yml`. Run `make sync` after
changing the shared model; do not edit it independently.
