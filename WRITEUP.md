# NetBird One-Click Marketplaces — Simple Meeting Brief

**Last checked:** July 31, 2026

> This is a planning brief and retains historical findings. The authoritative
> current release gates, provider submission fields, and step-by-step
> procedures are in `PUBLISHING.md`.

## The short version

We can support Akamai/Linode, DigitalOcean, Vultr, Hostinger, and Hetzner from
one codebase.

The main NetBird installation is shared. Each marketplace gets a small
"adapter" in the format that marketplace expects:

| Marketplace | What it expects |
| --- | --- |
| Akamai/Linode | A StackScript that runs Ansible |
| DigitalOcean | A prebuilt server image made with Packer |
| Vultr | Cloud-init Vendor Data |
| Hostinger | A public Docker Compose URL |
| Hetzner | A reusable snapshot made with Packer, configured by cloud-init or first login |

This avoids maintaining five separate NetBird installers. A NetBird update or
security fix is made once in the shared code, then each marketplace adapter is
tested and released.

**Important:** The architecture is ready, but the marketplace submissions are
not all ready yet.

## Current status

| Marketplace | Status | Plain-English explanation |
| --- | --- | --- |
| Akamai/Linode | Green/yellow — packaged | A provider-layout export, required `.credentials`, listing text, documentation, and assets are ready; the final Ubuntu 24.04 staging PR test remains. |
| DigitalOcean | Green/yellow — image passed | The official checker passed with 0 warnings and 0 failures and the live deployment passed; rebuild and retest the final tagged patch-level image. |
| Vultr | Green/yellow — live-tested | The imageless flow and shared deployment passed live testing; the final Marketplace metadata-variable path needs a private portal build. |
| Hostinger Deploy button | Green — live-tested | The exact generated Compose model passed Docker Manager, trusted TLS, health, STUN, and reboot tests. |
| Hostinger catalog | Unknown | Hostinger does not publish public rules for adding third-party apps to its curated catalog. |
| Hetzner private snapshot | Green/yellow — live-tested | Snapshot and cloud-init testing passed; rebuild the retained private artifact for the final patched Traefik and Alpine pins. |
| Hetzner Apps catalog | Blocked by provider | Hetzner currently says it does not accept suggestions for new apps. |

## What is already good

- One shared NetBird Docker Compose configuration.
- One shared Ansible installation and security configuration.
- Provider-specific entry points instead of five copied installers.
- Limited sudo administrator account.
- SSH hardening and protection against accidentally locking the user out.
- UFW firewall, Fail2ban, and Docker-aware firewall rules.
- Automatic trusted TLS certificates through Let's Encrypt.
- Required NetBird ports are documented.
- Versions are centrally controlled.
- Linode and DigitalOcean DNS automation exists.
- Vultr's existing variable names remain compatible.
- The Hostinger Compose file is generated from the shared source, preventing
  it from silently becoming different.

## Requirements that apply everywhere

Before any marketplace submission, we need to:

1. Publish this code in a public repository.
2. Create a real, immutable release tag. The adapters currently expect
   `https://github.com/PizzaLovingNerd/netbird-one-clicks.git` at tag `v0.1.0`, but that
   release is not currently available.
3. Add a repository license.
4. Add a list of every included component, version, and license.
5. Confirm the pinned NetBird `0.76.0`, Dashboard `2.90.8`, Traefik `3.7.10`,
   and Alpine `3.22.5` releases remain current and reviewed at tag time.
6. Prepare common marketing material:
   - Product name and short description
   - Long description/README
   - Support URL and support email
   - NetBird logo files
   - Screenshots
   - Installation and first-use instructions
   - Release notes
7. Test each installer on a brand-new server.
8. Verify:
   - DNS points only to the new server
   - HTTPS has a trusted certificate
   - The dashboard loads
   - Login and OIDC discovery work
   - The API rejects unauthenticated requests
   - TCP ports 80 and 443 work
   - UDP port 3478 works
   - Data survives a reboot
   - SSH remains accessible
   - A second installer run does not break the deployment
9. Remove test servers, snapshots, DNS records, and temporary credentials after
   testing.

## Akamai/Linode requirements

### What Akamai requires

- The Marketplace app must use a StackScript and Ansible.
- The StackScript should be small; Ansible should do the real installation.
- Installation should be hands-off. Required answers must be collected through
  StackScript fields.
- The StackScript needs proper error handling and cleanup.
- Current submissions support **Ubuntu 24.04 LTS**.
- Packages should be maintained and pinned to the latest stable versions.
- The server should have:
  - A limited sudo user
  - SSH hardening
  - A firewall
  - TLS/SSL
- Akamai expects initial credentials in
  `/home/<sudo-user>/.credentials`.
- Its guidelines call for Ansible Vault when handling initial secrets.
- A submission pull request needs:
  - The StackScript
  - A correctly formatted README
  - A 100–125-word description
  - Version number
  - Support URL
  - `DOCUMENTATION.md`
  - Suggested server plan
  - Credential and login instructions
  - Screenshots
  - Two brand colors
  - White and full-color vector logos

Official rules:
[Akamai contribution requirements](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/docs/CONTRIBUTING.md)
and
[Akamai development guidelines](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/docs/DEVELOPMENT.md).

### What we need to fix

- Stop advertising Ubuntu 26.04 for Akamai; use Ubuntu 24.04.
- Rename or also create the expected `.credentials` file. We currently create
  `.netbird-access.txt`.
- Decide how to meet Akamai's Ansible Vault guidance.
- Remove unnecessary installation artifacts after a successful deployment.
- Build the Akamai-specific README, documentation, and asset package.
- Package the files in Akamai's expected repository layout.
- Update and retest the NetBird version.

### Test status

- The temporary Linode API credential works.
- The `risi.industries` DNS zone exists in the Linode account.
- Public DNS for `risi.industries` currently returns `SERVFAIL`. Its registrar
  delegation must point to the correct Linode nameservers before
  `netbird.risi.industries` can receive a trusted certificate.
- No Linode test server has been created, so no Linode test charges have been
  incurred.

## DigitalOcean requirements

### What DigitalOcean requires

- A Droplet One-Click must be a prebuilt server image.
- DigitalOcean recommends building it with Packer.
- Ubuntu 24.04 and 26.04 are currently supported.
- The image needs cloud-init and OpenSSH.
- Use the smallest disk and server size that safely runs the application.
- Install current operating-system security updates.
- Use maintained official or trusted package repositories.
- The firewall must already be active when the image is checked.
- The image must not contain:
  - Root SSH keys
  - Shell history
  - Private build credentials
  - Unnecessary logs
- Run DigitalOcean's official cleanup script.
- Run DigitalOcean's official image-check script.
- The image check must have no blocking failures.
- A first-login setup script is allowed when information such as the domain
  cannot be known while building the image.
- A login message/MOTD and clear getting-started instructions are recommended.
- Build and test the final snapshot before sending its ID through the Vendor
  Portal.
- The Marketplace listing needs software versions, licenses, support details,
  instructions, and release information.

Official rules:
[DigitalOcean Marketplace partner image guide](https://github.com/digitalocean/marketplace-partners)
and
[DigitalOcean vendor guidelines](https://marketplace.digitalocean.com/vendors/guidelines-resources).

### What we need to fix

- Activate a safe minimum UFW policy during image preparation. At present, UFW
  is installed while building the image but is only activated after the
  customer's first login. DigitalOcean's checker treats an inactive firewall
  as a submission failure.
- Update and retest the NetBird version.
- Build a real snapshot and save the official checker results.
- Test a new Droplet created from that snapshot.
- Prepare the Marketplace listing and getting-started documentation.

The image intentionally requires at least 2 GB RAM. This limits the available
Droplet plans, but it is acceptable if 2 GB is NetBird's real minimum.

### Test status

- The temporary DigitalOcean API credential works.
- The account is active and currently permits up to ten Droplets.
- `stillos.pro` exists in the DigitalOcean DNS account.
- `stillos.pro` is publicly delegated to DigitalOcean's nameservers.
- `netbird.stillos.pro` does not currently have an A record, which is expected
  before the test server is created.
- No DigitalOcean Droplet or snapshot has been created, so no DigitalOcean test
  charges have been incurred.

## Vultr requirements

### What Vultr requires

- A verified Marketplace vendor account and Publisher Agreement.
- An application profile containing its name, OS, description, and support
  information.
- A public README and customer-facing application instructions.
- Icons and screenshots. Gallery images should use an 8:5 ratio, preferably
  800×500 pixels.
- Marketplace variable names must:
  - Use lowercase snake_case
  - Contain no more than 15 characters
- Provisioning reads variables through Vultr's Metadata API using the
  `METADATA-TOKEN: vultr` header.
- Vultr recommends an "imageless" app using cloud-init Vendor Data where
  possible.
- Use the smallest practical filesystem. Vultr provides the
  `marketplace-2c-2gb` build plan with 2 CPUs, 2 GB RAM, and an 8 GB disk.
- The selected OS image must contain a compatible version of cloud-init.
- The `vultr` kernel option is required for Bare Metal. It is optional, but
  recommended, for cloud-only deployments.
- Test a private build before making it live.
- Submit the public application for Vultr's review.

Official rules:
[Vultr Marketplace reference guide](https://docs.vultr.com/platform/marketplace/reference-guide).

### What is already compliant

- We use the recommended imageless Vendor Data approach.
- `nb_domain`, `acme_email`, and `admin_user` meet the 15-character and naming
  rules.
- The required metadata authentication header is present.
- Provisioning calls the shared installer instead of maintaining a separate
  Vultr installer.

### What still needs attention

- Review the existing live Vultr portal settings, instructions, artwork, and
  support information.
- Explicitly decide whether the app is cloud-only or also supports Bare Metal.
- Verify cloud-init and the kernel setting on the selected base image.
- Consider blocking SSH while the longer provisioning process runs, as Vultr
  recommends.
- Improve DNS setup. The current installation waits for the customer to point
  DNS after the new IP is known, so it is not completely hands-off.
- Run a private deployment and complete Vultr's publish/review process.

**Testing is paused until explicitly authorized. No Vultr API calls have been
made.**

## Hostinger requirements

Hostinger has two different things that can be called "one-click."

### Option 1: Deploy on Hostinger button

This is publicly documented and supported:

- Host the Docker Compose file at a public URL.
- Put that URL in Hostinger's official Deploy button.
- The user needs a VPS with Hostinger's Docker OS template.
- The Compose file must be valid and use public container images.
- Required environment variables must be supplied.
- Ports, volumes, and restart policies must be valid.
- Host firewall rules are managed separately in hPanel.

Official documentation:
[Deploy on Hostinger button](https://www.hostinger.com/support/deploy-on-hostinger-button/)
and
[Hostinger Docker Manager](https://www.hostinger.com/support/12040815-how-to-deploy-your-first-container-with-hostinger-docker-manager/).

Our adapter follows this model. It needs:

- `NETBIRD_FQDN`
- `NETBIRD_ACME_EMAIL`
- Inbound 80/TCP, 443/TCP, and 3478/UDP

### Option 2: Hostinger's curated Docker Catalog

Hostinger publishes the list of catalog applications, but it does not publish a
third-party vendor submission process or a complete set of acceptance rules.

This means:

- We can ship the official public Deploy button ourselves.
- We cannot promise inclusion in Hostinger's catalog without speaking directly
  to Hostinger.
- A Hostinger partnership or product contact may be needed for catalog
  inclusion.

Official catalog:
[Hostinger Docker Catalog](https://www.hostinger.com/support/hostinger-docker-catalog-applications/).

### What still needs attention

- Publish the Compose file at an immutable public URL.
- Test whether Hostinger's button flow lets the user enter the two required
  environment variables before deployment.
- Test DNS, TLS, ports, persistent volumes, restart behavior, and logs.
- Decide whether the goal is the public Deploy button, curated-catalog
  inclusion, or both.

**Testing is paused until explicitly authorized. No Hostinger API calls have
been made.**

## Hetzner requirements

Hetzner's own Cloud Apps use Packer-built snapshots and cloud-init for dynamic
first-boot setup. The repository now follows that model:

- Packer embeds the exact shared release into the snapshot.
- The image is cleaned of the Packer SSH key, host keys, machine identity,
  cloud-init state, package caches, logs, and unused blocks.
- Users can configure the instance through generated, credential-free
  cloud-init data or the first interactive root login.
- The public address is read from Hetzner's instance metadata service.
- DNS is changed externally, keeping DNS API credentials out of instance
  metadata and logs.

Hetzner's public Apps repository currently does not accept new application
suggestions. The immediate deliverable is therefore a tested private snapshot,
with the same artifact available for a direct review if Hetzner reopens
submissions.

### Test status

- Packer 1.16.0 and the official Hetzner plugin accept the template.
- Bash, YAML, and Ansible syntax checks pass.
- Snapshot `414904270` built successfully from Ubuntu 24.04 and remains
  available as the tested private artifact.
- A clean `cx23` deployment in `fsn1` completed through credential-free
  cloud-init in 93 seconds.
- Trusted TLS, dashboard and OIDC health, API authentication, container
  health, required ports, host firewalls, limited-user SSH, root SSH disable,
  repeat installation, and reboot recovery all passed.
- The disposable server, temporary SSH key, and test-only DNS record were
  removed after the test. See `build/hetzner-test-report.md` for the test
  record.

## What the API keys do—and do not do

The temporary provider API keys let us create and remove test resources. They
do not automatically publish an app in a marketplace.

Marketplace publication still requires:

- Vendor approval
- Agreements
- Listing text
- Support ownership
- Artwork
- Manual review
- In some cases, private portal access

The credentials should be revoked immediately after testing.

## Main risks

### Security

- A leaked provider key can create or delete cloud resources.
- Test credentials must be short-lived and kept out of Git and chat.
- Marketplace images must not contain build keys, SSH keys, DNS tokens, or
  shell history.

### Cost

- Cloud test instances and snapshots create small temporary charges.
- Hostinger may require an ongoing VPS subscription rather than purely hourly
  testing.
- Every test resource should be tagged and deleted after evidence is saved.

### Maintenance

- Marketplace approval is not a one-time job.
- NetBird, Docker, Traefik, Ubuntu, and marketplace standards change.
- Each release needs automated checks plus periodic real-cloud testing.
- DigitalOcean and Hetzner image updates require new snapshots.
- Other marketplaces may also require a new build or review.

### Customer experience

- A DNS name is necessary for trusted HTTPS.
- DNS is the hardest part of making this truly "one click" because a new
  server's IP is not known until it is created.
- Linode and DigitalOcean can automate DNS when the customer supplies a
  provider token.
- Vultr, Hostinger, and Hetzner need a clear external DNS flow.

## Decisions needed from management

1. Approve one public repository, preferably
   `github.com/PizzaLovingNerd/netbird-one-clicks`.
2. Approve the repository license.
3. Assign an owner for Marketplace support requests.
4. Approve official NetBird branding, screenshots, and listing text.
5. Decide the supported NetBird/Ubuntu release policy.
6. Decide whether Vultr supports cloud instances only or Bare Metal too.
7. Decide whether Hostinger's public Deploy button is sufficient or whether we
   should pursue a direct catalog partnership.
8. Approve a small recurring budget for clean-cloud release testing.
9. Assign responsibility for updating marketplace images after NetBird and
   Ubuntu security releases.
10. Ask Hetzner whether NetBird can receive a direct Apps review while general
    new-app contributions remain closed.

## Suggested message for the meeting

> We have designed one shared NetBird installer with thin adapters for each
> provider, so we do not have to maintain five independent products. The core
> architecture is working, but Marketplace approval also requires
> provider-specific packaging, documentation, artwork, security checks, and
> live-cloud tests. Linode and DigitalOcean have a few concrete issues to fix;
> Vultr is already close to its recommended model; Hostinger's public Deploy
> button is supported; and a Hetzner snapshot is implemented even though its
> public Apps catalog is currently closed to new submissions.

## Immediate next steps

1. Publish and tag the repository.
2. Fix the Linode-specific submission differences.
3. Activate UFW safely in the DigitalOcean build image.
4. Correct the public nameserver delegation for `risi.industries`.
5. Run the Linode and DigitalOcean deployments and save redacted results.
6. Revoke their temporary API credentials.
7. After approval, prepare DNS and run Vultr and Hostinger tests.
8. Complete the documentation, license inventory, screenshots, and vendor
   portal submissions.
