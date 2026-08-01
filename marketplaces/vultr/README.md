# Vultr adapter

Vultr Marketplace uses a cloud-init-capable image plus vendor-data. Configure
these app variables in the Vendor Portal:

| Name | Required | Description |
| --- | --- | --- |
| `nb_domain` | Yes | Public FQDN, for example `netbird.example.com` |
| `acme_email` | Yes | Let's Encrypt account email |
| `admin_user` | No | Limited sudo username; default `netbirdadmin` |

The names comply with Vultr's 15-character app-variable limit. `vendor-data.yml`
reads them from the Vultr Metadata API using the required `METADATA-TOKEN`
header, then invokes the shared installer.

Use a supported Ubuntu 24.04 or 26.04 cloud-init image, select the smallest
Marketplace build filesystem that meets the 8 GB minimum, and retain Vultr's
required kernel/cloud-init setup. Users must attach an SSH key. The hostname
must resolve only to the instance IPv4 address before provisioning can finish.

This adapter intentionally preserves the existing Vultr public input names
`nb_domain` and `acme_email`.

The Vendor Data temporarily places an SSH deny rule first in UFW while
provisioning runs and removes it through an `EXIT` trap. This follows Vultr's
long-provisioning recommendation without leaving an ordinary failed run
permanently inaccessible.
