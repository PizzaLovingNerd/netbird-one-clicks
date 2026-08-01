# Akamai Cloud Marketplace listing data

- App name: NetBird
- Version: 0.1.0
- Operating system: Ubuntu 24.04 LTS
- Suggested plan: Shared CPU 2 GB (`g6-standard-1`) or larger
- Support URL: https://docs.netbird.io/help/netbird-support
- Support email: support@netbird.io
- Category: Security
- Brand color 1: `#F68330`
- Brand color 2: `#F05252`

## Marketplace description

NetBird is an open-source network security platform that creates secure,
WireGuard-based private networks between devices, servers, and infrastructure.
This Marketplace app deploys a self-hosted NetBird control plane with the
management service, signal service, relay, embedded identity provider,
administration dashboard, and automatic HTTPS in one consistent installation.
The deployment creates a limited sudo administrator, hardens SSH, configures
UFW and Fail2ban, and verifies the public dashboard and authenticated API. A
public hostname is required for trusted TLS. Linode DNS can be configured
automatically with an optional scoped API token, or users can create the A
record before deployment. Persistent Docker volumes retain NetBird data,
configuration, and certificates across service restarts and server reboots.

## Submission assets

- Full-color vector: `../../assets/netbird-color.svg`
- White vector: `../../assets/netbird-white.svg`
- Dashboard and login screenshots: capture from the tagged release candidate
  without customer data and add them to the Akamai pull request asset archive.
