# Vultr Marketplace portal data

- App name: NetBird Self-Hosted
- Operating system: Ubuntu 24.04 LTS
- Description: Self-hosted secure networking with NetBird and WireGuard.
- Support URL: https://docs.netbird.io/help/netbird-support
- Support email: support@netbird.io
- Website URL: https://netbird.io/
- Category: Security
- Public URL slug: `netbird`
- Repo URL: leave blank, as directed by Vultr
- Deployment scope: Cloud Compute only; Bare Metal is not declared supported

## Readme

NetBird is an open-source network security platform that creates secure,
WireGuard-based private networks between devices, servers, and infrastructure.
This Marketplace app deploys a self-hosted control plane with its dashboard,
embedded identity provider, relay, automatic HTTPS, limited administrator,
host firewall, and Fail2ban protection. The deployment uses Vultr's recommended
imageless Vendor Data model and preserves NetBird configuration, data, and
certificates in Docker volumes.

A public hostname must resolve to the instance before certificate issuance.
The app requires a Cloud Compute plan with at least 2 GB RAM and 8 GB disk.
Inbound TCP 80 and 443 and UDP 3478 must be reachable.

## Variables

| Label | Name | Type | Required |
| --- | --- | --- | --- |
| Public NetBird hostname | `nb_domain` | Text field | Yes |
| Let's Encrypt account email | `acme_email` | Text field | Yes |
| Limited sudo username | `admin_user` | Text field | No |

## Application instructions

Your NetBird deployment is provisioning at `{{ip}}`. SSH is temporarily
blocked until the automated installation finishes.

The dashboard hostname is `{{nb_domain}}`. When HTTPS becomes available, open
`https://{{nb_domain}}/` and create the first NetBird administrator.

Connect over SSH using the key selected at deployment and the limited user
`{{admin_user}}` (or `netbirdadmin` when no value was supplied). Access notes
and the generated sudo password are stored in:

```text
/home/<admin-user>/.netbird-access.txt
```

For support, see https://docs.netbird.io/help/netbird-support.

## Build and artwork

Use **Build from Vendor Data**, Ubuntu 24.04 LTS, and
`marketplaces/vultr/vendor-data.yml`. Select the Marketplace 2 CPU / 2 GB / 8
GB build plan. Upload the approved NetBird icon plus current redacted login and
dashboard images as PNG files at 800×500 (8:5). External image links are not
accepted by the Vultr editor.
