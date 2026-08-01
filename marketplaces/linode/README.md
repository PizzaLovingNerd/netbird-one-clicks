# Akamai Cloud / Linode adapter

This adapter follows the Marketplace StackScript + Ansible convention. The
StackScript translates Linode UDF variables to the shared installer contract,
clones an immutable release, and invokes the common playbook.

## Submission

1. Publish the unified repository.
2. Set `ONECLICKS_REPOSITORY` and pin `ONECLICKS_REF` to a tested release tag in
   `stackscript.sh`.
3. Submit the StackScript and repository to the Akamai Compute Marketplace
   repository/process.
4. Mark only Ubuntu 24.04 LTS as compatible and require 2 GB RAM.

The optional token needs Domains read/write access to the existing DNS zone.
Without it, the requested hostname must already resolve only to the new
instance's IPv4 address. Users must select an account SSH key when root SSH is
disabled.

Linode DNS Manager only serves zones while the account has at least one active
Linode. This is normally satisfied by the instance being deployed, but a new
or previously inactive account can have a short authoritative-DNS convergence
delay during first boot. The shared installer waits for exact answers from
both public resolvers before requesting TLS.

Deployment logs are written to `/var/log/stackscript.log` and
`/var/log/netbird-one-click.log`.

The generated sudo password and access instructions are written to the Akamai
Marketplace-standard `/home/<admin-user>/.credentials` file with mode `0600`.
