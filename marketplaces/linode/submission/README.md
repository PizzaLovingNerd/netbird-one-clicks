# NetBird

NetBird is an open-source network security platform that connects devices and
infrastructure through secure WireGuard-based private networks. This app
deploys a self-hosted NetBird control plane with its dashboard, embedded
identity provider, relay, and automatic HTTPS.

## Software included

| Software | Version | Description |
| --- | --- | --- |
| NetBird combined server | 0.76.0 | Management, signal, relay, identity, API, and STUN |
| NetBird Dashboard | 2.90.8 | Browser administration interface |
| Traefik | 3.7.10 | TLS termination and reverse proxy |
| Docker Engine and Compose | Current supported Ubuntu package | Container runtime |

Supported distribution: Ubuntu 24.04 LTS.

## Deployment details

Deploy on a Shared CPU 2 GB plan or larger and select an account SSH key. A
public hostname is required. The StackScript can create the A record when a
Linode API token with Domains read/write access is supplied; otherwise create
the record before deployment.

Provisioning creates a limited sudo account, configures UFW and Fail2ban,
disables direct root SSH when requested, obtains a trusted Let's Encrypt
certificate, and verifies the dashboard and API. Access instructions and the
generated sudo password are stored in `/home/<admin-user>/.credentials`.

## Resources

- [NetBird documentation](https://docs.netbird.io/)
- [NetBird support](https://docs.netbird.io/help/netbird-support)
- [NetBird source and licenses](https://github.com/netbirdio/netbird)
