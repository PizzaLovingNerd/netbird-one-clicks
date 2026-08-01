# One-click architecture and marketplace fit

This document explains how the NetBird one-clicks share one deployment
implementation while using the native delivery mechanism expected by each
marketplace. It also records where repository automation ends and a provider's
submission or review process begins.

For the current release gate and exact portal/PR submission procedures, use
`PUBLISHING.md`.

The marketplace guidance cited here was reviewed on 2026-07-31. Provider rules
and portals can change, so the linked guidance must be checked again before
each submission.

## Executive summary

There is one application model, one host installer, and several thin delivery
adapters:

```text
                         immutable release tag
                                  |
          +-----------------------+-----------------------+
          |                       |                       |
   Linode StackScript      Vultr vendor-data     Provider Packer images
   maps UDF variables      maps app metadata    DigitalOcean and Hetzner
          |                       |             embed the exact release
          +-----------------------+-----------------------+
                                  |
                         common input contract
                                  |
                         shared Ansible roles
                preflight -> DNS -> host -> app -> verify
                                  |
                     canonical Docker Compose model
                                  |
                  NetBird + dashboard + Traefik + state

   Hostinger Deploy button -> generated copy of the same Compose model
                              (host management remains with hPanel)
```

This separation is deliberate:

- A marketplace adapter owns only provider-native packaging, input collection,
  and provider APIs.
- The shared installer owns host preparation, security policy, installation,
  and end-to-end verification.
- `shared/docker-compose.yml` owns the runtime application topology.
- A release tag is the immutable unit distributed to every marketplace.

The result is one logical product with four packaging formats, rather than four
independent installers.

## Design goals

The architecture is intended to provide:

1. **A consistent product:** every target runs the same NetBird services,
   routes, persistent volumes, ports, and health checks.
2. **Native marketplace delivery:** StackScript, image, cloud-init, and
   Compose-only platforms each receive the artifact they expect.
3. **A small provider surface:** provider scripts translate inputs and then
   hand control to shared code.
4. **Safe repeatability:** host roles and config generation are idempotent,
   secrets survive reruns, and release artifacts install immutable versions.
5. **Auditable releases:** generated-file comparison, syntax checks, Compose
   validation, Ansible checks, and Packer validation catch drift before a
   marketplace review.

This repository does not automate vendor enrollment, contractual approval,
listing copy, pricing, screenshots, icons, support contacts, or final provider
acceptance. Those are marketplace control-plane responsibilities.

## Sources of truth

| Concern | Authoritative source | Derived or consuming artifacts |
| --- | --- | --- |
| Runtime topology | `shared/docker-compose.yml` | Hostinger Compose copy; `/opt/netbird/docker-compose.yml` on installed hosts |
| Host installation | `getting-started.yml` and `ansible/roles/` | Linode, DigitalOcean, Vultr, Hetzner, and generic hosts |
| External installer contract | `getting-started.sh` and `ansible/group_vars/all.yml` | Provider adapters |
| Runtime image releases | `versions.env` release catalog | Compose image defaults, checked for equality by validation |
| Supported resources, OSes, and ports | `marketplaces/manifest.yml` | Marketplace listing and release configuration |
| Provider packaging | `marketplaces/<provider>/` | The artifact submitted to or referenced by that provider |
| Release procedure | `docs/RELEASING.md` | Marketplace submissions |

`versions.env` and the Compose defaults are controlled duplication: Compose
must remain independently deployable, while the release catalog must remain
machine-readable. `scripts/validate.sh generated` compares every catalog value
with its Compose default, so they cannot drift in a valid change.

No provider may maintain a second Compose stack, copy the Ansible roles, or
implement an alternative health-check path.

## Common provider boundary

Provider-specific fields are translated once, at the edge, into this contract:

| Variable | Required | Meaning |
| --- | --- | --- |
| `MARKETPLACE_PROVIDER` | No | `generic`, `linode`, `digitalocean`, `vultr`, or `hetzner` |
| `NETBIRD_FQDN` | Yes | Public NetBird hostname |
| `NETBIRD_ACME_EMAIL` | Yes | Let's Encrypt account email |
| `NETBIRD_ADMIN_USER` | No | Limited sudo user; defaults to `netbirdadmin` |
| `NETBIRD_DISABLE_ROOT_SSH` | No | Disable direct root SSH after copying the provider key; defaults to `true` |
| `NETBIRD_DNS_TOKEN` | No | Ephemeral provider DNS credential |
| `NETBIRD_DNS_ZONE` | With token | Existing provider DNS zone |
| `NETBIRD_PUBLIC_IPV4` | No | Explicit public IPv4 override for NAT-based providers |
| `NETBIRD_INSTALLER_DIR` | Internal | Location of the checked-out or embedded release |

Examples of boundary translation:

- Linode's `DOMAIN`, `SUBDOMAIN`, and `TOKEN_PASSWORD` UDF environment
  variables become `NETBIRD_FQDN`, `NETBIRD_DNS_ZONE`, and
  `NETBIRD_DNS_TOKEN`.
- Vultr's `nb_domain`, `acme_email`, and `admin_user` application variables are
  fetched from the metadata service and mapped to the same shared names.
- DigitalOcean collects the shared names interactively because a Droplet image
  cannot know the customer's domain at build time.
- Hetzner accepts the names through generated cloud-init user data or collects
  them at the first interactive root login. Its public IPv4 is read from the
  link-local Hetzner metadata service.
- Hostinger supplies `NETBIRD_FQDN` and `NETBIRD_ACME_EMAIL` directly to
  Compose; it does not run the host contract.

Provider names never leak into the application model. Provider DNS logic is
the only provider-specific behavior below the adapter boundary.

## Shared installation flow

`getting-started.sh` is the bootstrap and operator interface. It requires root,
installs Ansible into `/opt/netbird-one-click-venv`, collects or validates
inputs, protects logs and temporary values with a restrictive umask, and calls
the stable `getting-started.yml` entry point.

The playbook runs five ordered roles:

1. **Preflight**
   - Requires Ubuntu 24.04 or 26.04, x86-64 or ARM64, at least 2 GB RAM,
     and at least 8 GB free disk.
   - Validates the hostname, email, administrator name, provider, and DNS
     inputs.
   - Selects and validates the public IPv4 address.
   - Refuses to disable root SSH unless a valid provider-injected SSH key can
     first be copied to the limited administrator.
   - Refuses to take over an unmanaged local user.
2. **DNS**
   - Optionally creates or updates one A record through the Linode or
     DigitalOcean API.
   - Keeps the API token in process memory and marks API tasks `no_log`.
   - Requires two public recursive resolvers to return exactly the instance
     IPv4 address before certificate issuance.
3. **Host**
   - Installs Docker from Docker's signed Ubuntu repository.
   - Creates a limited sudo administrator and copies the provider SSH key.
   - Installs unattended-upgrades and enables UFW, Fail2ban, and a
     Docker-aware ingress chain.
   - Allows only 22/tcp, 80/tcp, 443/tcp, and 3478/udp inbound.
   - Applies the SSH policy only after its configuration validates.
4. **NetBird**
   - Copies the canonical Compose model to `/opt/netbird`.
   - Writes only deployment environment values beside it.
   - Validates Compose, pulls the pinned images, starts the services, and waits
     for all long-running containers to report healthy.
5. **Post-install**
   - Verifies trusted public TLS, OIDC discovery, authenticated API behavior,
     and the dashboard.
   - Writes protected access notes, installs the Marketplace MOTD, and records
     a completion marker.

The host phases are designed to be rerunnable. Application secrets are
generated only when `config.yaml` is absent and persist in the
`netbird_config` Docker volume.

## Canonical runtime model

`shared/docker-compose.yml` contains four services:

| Service | Responsibility |
| --- | --- |
| `netbird-config` | One-time generation of the NetBird YAML configuration and long random secrets |
| `traefik` | HTTP-to-HTTPS redirect, Let's Encrypt, TLS termination, HTTP routing, and h2c routing for gRPC |
| `dashboard` | NetBird browser UI configured for the embedded identity provider |
| `netbird-server` | Combined management, signal, relay, embedded identity, API, and STUN service |

State is held in three named volumes:

- `netbird_config` for generated configuration and secrets;
- `netbird_data` for NetBird server data;
- `netbird_traefik_letsencrypt` for certificate state.

Only 80/tcp, 443/tcp, and 3478/udp are published by the application. SSH is a
host concern and is therefore absent from Compose. All containers have restart
policies, bounded JSON logs, and health checks. The config initializer is
atomic and idempotent: it writes a temporary file, moves it into place, and
retains existing configuration on later starts.

## Marketplace fit

“Fits” below means that the repository adopts the provider's documented
delivery mechanism and technical constraints. It does not guarantee approval;
the provider's current validator and human review remain authoritative.

### Akamai Cloud / Linode

**Native model.** Akamai describes Marketplace apps as a StackScript, Ansible
playbooks, and a Git repository. StackScripts run on first boot, support Bash
and user-defined fields, and expose those fields as environment variables.

**Repository implementation.**

- `marketplaces/linode/stackscript.sh` is a Bash StackScript with UDFs for the
  DNS zone, subdomain, ACME email, optional masked API token, limited user, and
  root-SSH policy.
- The adapter installs only its bootstrap dependencies, clones an immutable
  release tag, converts UDF variables to the common contract, and invokes the
  common playbook.
- The Ansible content uses roles and a stable entry playbook, matching the
  Marketplace's portable, modular model.
- Optional DNS automation uses the native Linode Domains API. With no token,
  the same shared DNS verification requires the record to exist already.
- Linode DNS Manager requires at least one active Linode before it serves an
  account's zones. The new marketplace instance satisfies that requirement,
  and the bounded dual-resolver gate handles the initial authoritative
  convergence period before TLS is requested.
- Logs are retained at `/var/log/stackscript.log` and
  `/var/log/netbird-one-click.log` for deployment diagnosis.

**Why this remains one source.** The StackScript contains no NetBird service
definition, host firewall implementation, or post-install verification. A
StackScript update changes only Linode's form and translation boundary; an
application update changes shared code once.

**Submission checks.**

- Import or submit the StackScript through the current Akamai Marketplace
  process and point it at a tested release tag.
- Configure only Ubuntu releases that the shared preflight accepts and require
  at least 2 GB RAM.
- Ensure listing fields and support materials are supplied outside this repo.

Official references:
[Marketplace app development model](https://github.com/akamai-compute-marketplace/marketplace-apps#marketplace-app-development-guidelines) and
[StackScript/UDF rules](https://techdocs.akamai.com/cloud-computing/docs/write-a-custom-script-for-use-with-stackscripts).

### DigitalOcean

**Native model.** DigitalOcean Droplet 1-Click Apps are submitted as validated
snapshots. Its partner guidance recommends Packer, requires supported OS and
connectivity packages, supplies cleanup and image-check scripts, and permits
instance-specific work such as domain setup on first login.

**Repository implementation.**

- `marketplaces/digitalocean/packer.pkr.hcl` creates a snapshot from a
  supported Ubuntu base and records its image ID in `build/manifest.json`.
- Packer embeds the exact repository state into
  `/opt/netbird-one-clicks`; it does not clone a moving branch on the customer
  Droplet.
- Image preparation installs Docker and Ansible dependencies without starting
  an unconfigured NetBird deployment.
- The build downloads DigitalOcean's official cleanup and image-check scripts
  from a pinned upstream commit, verifies their SHA-256 hashes, and runs both
  before snapshot creation.
- The first interactive root SSH login collects the domain, ACME email,
  administrator, root-SSH policy, and optional DigitalOcean DNS settings, then
  hands off to the shared installer.

**Why this remains one source.** Packer packages the shared roles and Compose
model as release payload. DigitalOcean-specific files control image lifecycle
and first-login behavior only.

**Intentional constraints and review items.**

- The image is built on a 2 GB plan because the application enforces a 2 GB
  minimum. DigitalOcean encourages the smallest inexpensive build Droplet so
  the broadest set of sizes can use an app; this product requirement
  intentionally excludes smaller plans and must be reflected in the listing.
- DigitalOcean documents `.bashrc` as its example first-login hook. This image
  uses `/etc/profile.d` with interactive-root, terminal, executable, and
  completion-marker guards. Confirm that equivalent behavior is accepted in
  the current review.
- Refresh the pinned cleanup/check commit and checksums deliberately during
  release maintenance; pinning makes builds reproducible but does not make an
  old validator current.

Official reference:
[DigitalOcean Marketplace partner image requirements and tooling](https://github.com/digitalocean/marketplace-partners).

### Vultr

**Native model.** Vultr supports an “imageless” Marketplace app built from
cloud-init Vendor Data. Application variables are read through the metadata
API using a `METADATA-TOKEN` header. Variable names must be lower-case
snake_case and no longer than 15 characters. Vultr requires a cloud-init OS and
recommends the smallest Marketplace filesystem.

**Repository implementation.**

- `marketplaces/vultr/vendor-data.yml` is valid cloud-config and installs a
  per-instance provisioning script through `write_files` and `runcmd`.
- `nb_domain`, `acme_email`, and `admin_user` satisfy the 15-character
  lower-case/underscore rule. The existing public names `nb_domain` and
  `acme_email` are intentionally stable.
- The script reads `app-<name>` endpoints from `169.254.169.254` with the
  required `METADATA-TOKEN: vultr` header.
- It clones an immutable release, translates metadata to the common contract,
  and runs the same Ansible installer used elsewhere.
- The documented 8 GB minimum matches Vultr's small Marketplace build
  filesystem; the selected image must retain cloud-init and the Vultr kernel
  option.

**Why this remains one source.** Vendor Data owns only first-boot retrieval and
translation. The NetBird stack and host changes live in the shared release it
invokes.

**Review item.** Vultr recommends blocking SSH while long provisioning scripts
run and re-enabling it on completion. The current adapter keeps provider-key
SSH available so an operator can diagnose installation. This is a documented
operational choice, not a technical Marketplace requirement; it should be
re-evaluated with Vultr during submission.

Official reference:
[Vultr Marketplace reference guide](https://docs.vultr.com/platform/marketplace/reference-guide).

### Hostinger

**Native model.** Hostinger's Deploy button accepts a public
`docker-compose.yml` through the `compose_url` query parameter and opens it in
Docker Manager. Hostinger manages the VPS and Docker environment around that
Compose project.

**Repository implementation.**

- `marketplaces/hostinger/docker-compose.yml` is a generated, byte-for-byte
  copy of `shared/docker-compose.yml`.
- The Deploy button points to that file at an immutable release URL.
- `NETBIRD_FQDN` and `NETBIRD_ACME_EMAIL` are collected as Compose environment
  values before deployment.
- Persistent named volumes, container restart policies, health checks, TLS,
  and published application ports all travel in the Compose artifact.
- Hostinger's hPanel remains responsible for VPS firewall configuration and
  SSH. The adapter documents inbound 80/tcp, 443/tcp, and 3478/udp and does not
  pretend the Compose boundary can configure the host.

**Why this remains one source.** `make sync` copies the canonical model and
`make validate` uses `cmp` to reject any hand-edited Hostinger variant. The
provider artifact exists only because Hostinger needs a stable public URL at a
marketplace-specific path.

Official reference:
[Deploy on Hostinger button](https://www.hostinger.com/support/deploy-on-hostinger-button/).

### Hetzner Cloud

**Native model.** Hetzner Cloud Apps are reusable snapshots produced with
Packer and initialized with cloud-init. Hetzner's public Apps source mirrors
the Packer templates and metadata used by its internal build system.

**Repository implementation.**

- `marketplaces/hetzner/packer.pkr.hcl` builds a supported Ubuntu snapshot and
  embeds the exact repository contents in `/opt/netbird-one-clicks`.
- Image preparation installs the shared dependencies and activates a safe
  minimum firewall without starting an unconfigured NetBird deployment.
- Cleanup removes the Packer key, SSH host keys, machine identity, cloud-init
  state, logs, package caches, and unused filesystem blocks before snapshotting.
- `render-user-data.sh` creates credential-free cloud-init data for automated
  deployment. Interactive first-root-login setup remains available as a
  fallback.
- The shared preflight reads the server's public IPv4 from Hetzner's metadata
  endpoint rather than assuming the default interface address is public.
- DNS is intentionally updated outside the server. This avoids persisting a
  DNS API token in instance user data or cloud-init logs.

**Publication status.** Hetzner's Apps repository currently says it does not
accept suggestions for new applications. The adapter is therefore a private
snapshot and reproducible test target until Hetzner reopens submissions or
accepts NetBird through a direct provider review.

Official references:
[Hetzner Apps build model](https://github.com/hetznercloud/apps),
[Hetzner Packer builder](https://developer.hashicorp.com/packer/integrations/hetznercloud/hcloud/latest/components/builder/hcloud), and
[Hetzner instance metadata](https://docs.hetzner.cloud/reference/cloud#metadata-service).

## Cross-marketplace compliance matrix

| Requirement | Linode | DigitalOcean | Vultr | Hostinger | Hetzner |
| --- | --- | --- | --- | --- | --- |
| Provider-native entry point | StackScript | Packer snapshot | cloud-init Vendor Data | Compose URL | Packer snapshot |
| Immutable application source | Release tag cloned | Release embedded at build | Release tag cloned | Release-tag raw URL | Release embedded at build |
| User-input mechanism | UDFs | First root login | App variables/metadata | Compose environment | cloud-init or first root login |
| Shared host hardening | Yes | Yes, after first login | Yes | Outside Compose; hPanel-owned | Yes, after first boot |
| Shared Compose model | Installed by Ansible | Installed by Ansible | Installed by Ansible | Generated exact copy | Installed by Ansible |
| DNS automation | Optional Linode API | Optional DigitalOcean API | Pre-existing DNS | Pre-existing DNS | External/pre-existing DNS |
| Trusted TLS gate | Shared post-install verification | Shared post-install verification | Shared post-install verification | Container health plus operator verification | Shared post-install verification |
| Marketplace image validation | Not image-based | Official cleanup and image check | Vultr build/live checks | Not image-based | Packer build and live checks |
| Portal/listing assets in repo | No | No | No | Deploy-button instructions only | No; submissions closed |

## Maintaining all one-clicks from one source

The maintenance rule is “change the lowest shared layer that owns the
behavior.”

### Application or routing change

1. Edit `shared/docker-compose.yml`.
2. If image releases changed, update `versions.env` in the same change.
3. Run `make sync` to regenerate the Hostinger artifact.
4. Run `make validate`.
5. Exercise the public health checks on a clean generic instance before
   provider testing.

Do not edit `marketplaces/hostinger/docker-compose.yml` directly.

### Host, security, or verification change

1. Edit the appropriate shared Ansible role.
2. Keep provider conditions out of shared tasks unless they represent a real
   provider API or platform difference.
3. Run Ansible syntax/lint checks and test a clean install and a rerun.
4. Rebuild the DigitalOcean image because its embedded release changed; Linode
   and Vultr receive the change when their pinned release ref is advanced.

### Provider form or packaging change

1. Edit only `marketplaces/<provider>/`.
2. Translate new fields into the existing common contract where possible.
3. Extend the contract only when the underlying product needs new behavior.
4. Re-run the provider's own build or portal validation.

### Release change

1. Update version inputs and generated files.
2. Run the complete local and CI validation suite.
3. Test every artifact on a clean supported instance.
4. Tag the repository.
5. Pin Linode and Vultr to the tag, build DigitalOcean and Hetzner from the
   tag's exact contents, and use the tag in Hostinger's raw Compose URL.
6. Record and submit provider-specific artifacts following
   `docs/RELEASING.md`.

Never publish an adapter that installs from `main` or another moving ref.

## Drift prevention and validation

The validation pipeline enforces the parts of single-source maintenance that
can be checked without creating provider resources:

- Bash parsing and ShellCheck for all shell entry points;
- YAML parsing and yamllint;
- generated Hostinger Compose equality;
- central image-version equality with Compose defaults;
- idempotent generation and preservation of NetBird configuration secrets;
- Ansible syntax and lint;
- Docker Compose model validation;
- Packer formatting, initialization, and validation;
- CI execution on pull requests and pushes to `main`.

Provider end-to-end tests remain necessary because CI cannot emulate DNS
propagation, marketplace metadata, image cleanup, cloud-init ordering,
provider SSH-key injection, public certificate issuance, or portal policy.

## Adding another marketplace

A new target should be added only as another adapter:

1. Identify the provider's native delivery artifact and current publication
   requirements.
2. Add `marketplaces/<provider>/` and register its artifact in
   `marketplaces/manifest.yml`.
3. Map provider inputs to the common contract.
4. Invoke `getting-started.sh --provider <provider>` for a host-capable target,
   or publish a generated copy of the canonical Compose model for a
   Compose-only target.
5. Add a provider DNS hook only if the provider supplies a DNS API and the
   product requires it.
6. Extend validation for every generated artifact or duplicated release value.
7. Document any requirement that must be satisfied in the provider portal.

A proposed adapter is too thick if it defines NetBird services, creates its
own administrator policy, opens a different set of application ports, or
implements separate health checks.

## Submission-readiness checklist

Before claiming any one-click is marketplace-ready:

- Re-read the provider guidance linked above.
- Verify supported OS identifiers are currently offered by that provider.
- Confirm the release tag and container image tags are immutable.
- Run `make sync && make validate`.
- Run the provider's current image/build checks, not only the repository's
  pinned tooling.
- Deploy on the minimum supported plan with a provider-injected SSH key.
- Test clean installation, interrupted-install recovery, rerun behavior, and
  reboot persistence.
- Verify exact DNS, trusted TLS, dashboard, OIDC discovery, API
  authentication, gRPC connectivity, relay, and 3478/udp.
- Confirm the firewall exposes only the documented ports.
- Confirm no build credentials, API tokens, SSH keys, shell history, or
  instance logs are captured in a published image.
- Supply accurate listing copy, license, support contact, privacy/security
  information, screenshots, icons, and customer instructions in the provider
  portal.
- Record provider reviewer exceptions or decisions beside the release notes.

This checklist is the final boundary: the repository makes the four delivery
paths consistent and reviewable, while the live marketplace review determines
whether each submitted release is accepted.
