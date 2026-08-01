# Hetzner Cloud adapter

Hetzner Cloud Apps are static snapshots built with Packer and configured by
cloud-init or on first login. This adapter embeds the shared repository in a
reusable Ubuntu snapshot, removes build credentials and machine identity, and
defers the hostname-specific NetBird installation until the resulting server
is launched.

## Build the snapshot

```bash
export HCLOUD_TOKEN='temporary-build-token'
mkdir -p build
packer init marketplaces/hetzner/packer.pkr.hcl
packer build marketplaces/hetzner/packer.pkr.hcl
```

The snapshot ID is written to `build/hetzner-manifest.json`. Packer deletes
its temporary build server, but the resulting snapshot remains billable until
you delete it.

## Launch

Create a server from the snapshot with an account SSH key and at least 2 GB
RAM. Point the intended hostname at its public IPv4 address, then log in as
root; the interactive setup invokes the shared installer.

For a non-interactive deployment, render cloud-init user data before creating
the server:

```bash
marketplaces/hetzner/render-user-data.sh \
  --domain netbird.example.com \
  --email admin@example.com \
  > build/hetzner-user-data.yml
```

Supply that file as the server's user data. The hostname must resolve to the
new server before provisioning finishes. The renderer deliberately accepts no
DNS credential; update DNS outside the instance so a provider token is never
stored in Hetzner metadata or cloud-init logs.

If a Hetzner Cloud Firewall is attached, allow 22/tcp, 80/tcp, 443/tcp, and
3478/udp. Hetzner Cloud Firewalls are stateless; NetBird's upstream guidance
also calls for the host's UDP ephemeral response range when such a firewall is
used. The image's UFW and Docker-aware rules remain the authoritative host
firewall.

Hetzner currently does not accept new third-party applications in its official
Apps repository. This artifact can be used as a private snapshot and is ready
for provider review if submissions reopen.
