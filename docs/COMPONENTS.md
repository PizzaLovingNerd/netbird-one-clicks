# Included software and licenses

This inventory applies to one-click release `0.1.0`. Runtime container tags
are pinned in `versions.env`; rebuild and retest every provider artifact when a
pin changes.

| Component | Release | Purpose | License |
| --- | --- | --- | --- |
| NetBird combined server | `0.76.0` | Management, signal, relay, identity, API, and STUN | [AGPL-3.0](https://github.com/netbirdio/netbird/blob/v0.76.0/combined/LICENSE) |
| NetBird Dashboard | `2.90.8` | Browser administration UI | [AGPL-3.0](https://github.com/netbirdio/dashboard/blob/v2.90.8/LICENSE) |
| Traefik | `3.7.10` | TLS termination and reverse proxy | [MIT](https://github.com/traefik/traefik/blob/v3.7.10/LICENSE.md) |
| Alpine Linux | `3.22.5` | One-shot configuration container | [Package-specific open-source licenses](https://pkgs.alpinelinux.org/packages?branch=v3.22) |
| Ansible community package | `14.0.0` | Host provisioning | [GPL-3.0](https://github.com/ansible/ansible/blob/devel/COPYING) |
| Docker Engine and Compose | Current signed Ubuntu-repository release at image build or deployment | Container runtime | [Apache-2.0](https://github.com/docker/docker-ce/blob/master/LICENSE) |
| Ubuntu | 24.04 LTS; 26.04 LTS where the provider accepts it | Host operating system | [Ubuntu licensing](https://ubuntu.com/legal/intellectual-property-policy) |

CI and image builds pin Packer `1.16.0`, the DigitalOcean plugin `1.4.1`, and
the Hetzner Cloud plugin `1.7.2`. Update these deliberately and validate both
image definitions when changing the build toolchain.

The DigitalOcean and Hetzner images contain the provisioning source and its
Python virtual environment so the installation can be audited and safely
rerun. Linode and Vultr retain the checked-out release payload but remove Git
metadata after a successful install. Hostinger consumes only the generated
Compose model.

This repository's original adapter and provisioning code is distributed under
the BSD 3-Clause license in `LICENSE`. That license does not replace or modify
the licenses of the software installed by these artifacts.
