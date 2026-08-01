# Updating from NetBird's upstream quick-start

Use this runbook whenever NetBird publishes a changed `getting-started.sh`.
The upstream script is a specification and comparison source for this
repository; it is not a drop-in replacement for the local file with the same
name.

## Current upstream baseline

- NetBird release: `v0.76.0`
- Release asset: `getting-started.sh`
- SHA-256:
  `0fc775486dbf516c91cdd3ca583ab5f83fe316b950d9a5558be8003d190449d8`
- Tagged source:
  `infrastructure_files/getting-started.sh` at `v0.76.0`

Update this baseline only after the new release has passed the static and live
checks in this document.

Official upstream sources:

- [Latest NetBird release](https://github.com/netbirdio/netbird/releases/latest)
- [Upstream quick-start source](https://github.com/netbirdio/netbird/blob/main/infrastructure_files/getting-started.sh)
- [Upstream self-hosting guide](https://docs.netbird.io/selfhosted/selfhosted-guide)

## Do not overwrite the local installer

Do not copy upstream `getting-started.sh` over this repository's
`getting-started.sh`. The files have different responsibilities:

- Upstream's script is a general-purpose interactive renderer supporting
  multiple reverse proxies and optional deployment modes.
- This repository's `getting-started.sh` is a guarded marketplace bootstrap.
  It validates provider inputs, prepares Ansible, and invokes the shared
  marketplace playbook.
- `shared/docker-compose.yml` is the canonical NetBird application model here.
- `getting-started.yml` is the stable Ansible entry point. Most provisioning
  changes belong in a role under `ansible/roles/`, not directly in that file.

Replacing the local installer would remove DNS automation, image preparation,
limited-user creation, SSH policy, firewall rules, idempotence, provider
credentials files, and the common behavior expected by the five adapters.

## 1. Fetch and authenticate the new upstream release

Start from a clean checkout and create a review branch:

```bash
git switch main
git pull --ff-only
git switch -c update-netbird-vX.Y.Z
mkdir -p build/upstream-review
```

Set the old and new tags. `UPSTREAM_OLD_TAG` must match the baseline recorded
above; never compare only against the moving `main` branch.

```bash
export UPSTREAM_OLD_TAG=v0.76.0
export UPSTREAM_NEW_TAG=vX.Y.Z

curl --fail --silent --show-error --location \
  "https://github.com/netbirdio/netbird/releases/download/${UPSTREAM_OLD_TAG}/getting-started.sh" \
  --output "build/upstream-review/getting-started-${UPSTREAM_OLD_TAG}.sh"

curl --fail --silent --show-error --location \
  "https://github.com/netbirdio/netbird/releases/download/${UPSTREAM_NEW_TAG}/getting-started.sh" \
  --output "build/upstream-review/getting-started-${UPSTREAM_NEW_TAG}.sh"
```

Verify the new file against the digest published in GitHub's release metadata:

```bash
curl --fail --silent --show-error \
  "https://api.github.com/repos/netbirdio/netbird/releases/tags/${UPSTREAM_NEW_TAG}" \
  --output build/upstream-review/release.json

published_digest="$(jq -r \
  '.assets[] | select(.name == "getting-started.sh") | .digest' \
  build/upstream-review/release.json)"
downloaded_digest="sha256:$(sha256sum \
  "build/upstream-review/getting-started-${UPSTREAM_NEW_TAG}.sh" \
  | cut -d' ' -f1)"
test "${downloaded_digest}" = "${published_digest}"
```

Also verify that the release asset matches the source at the immutable tag:

```bash
curl --fail --silent --show-error --location \
  "https://raw.githubusercontent.com/netbirdio/netbird/${UPSTREAM_NEW_TAG}/infrastructure_files/getting-started.sh" \
  --output "build/upstream-review/getting-started-${UPSTREAM_NEW_TAG}-source.sh"

cmp \
  "build/upstream-review/getting-started-${UPSTREAM_NEW_TAG}.sh" \
  "build/upstream-review/getting-started-${UPSTREAM_NEW_TAG}-source.sh"
```

Stop if the asset has no published digest, the checksum differs, or the tagged
source differs from the release asset. Resolve that discrepancy with NetBird
upstream before adopting the release.

## 2. Review every upstream change

Generate a complete diff. Exit status `1` is expected when differences exist:

```bash
git diff --no-index -- \
  "build/upstream-review/getting-started-${UPSTREAM_OLD_TAG}.sh" \
  "build/upstream-review/getting-started-${UPSTREAM_NEW_TAG}.sh" \
  >build/upstream-review/getting-started.diff || test $? -eq 1
```

Review the upstream release notes and the tag comparison as well as the raw
script diff. A generated Compose or configuration change can be difficult to
recognize from a shell diff alone.

```text
https://github.com/netbirdio/netbird/compare/v0.76.0...vX.Y.Z
```

Classify every changed hunk into one of these categories and record the result
in the pull request:

- Required application or protocol change
- Security fix or hardening change
- Image/version update
- Input, validation, or default change
- Health check or readiness change
- New persistent data or secret
- Optional upstream feature outside the marketplace product scope
- Refactor or message-only change with no deployment impact

Do not silently discard a hunk. For excluded optional features, document why
the marketplace one-click remains intentionally narrower.

## 3. Translate changes into the local architecture

Use this mapping rather than copying upstream functions verbatim.

| Upstream change | Update here |
| --- | --- |
| Service, command, label, network, port, volume, dependency, or container health change | `shared/docker-compose.yml` |
| NetBird server configuration, auth, relay, STUN, trusted proxy, datastore, or encryption change | The `netbird-config` initializer in `shared/docker-compose.yml` |
| Server, Dashboard, Traefik, or helper image tag | `versions.env`, Compose defaults, `marketplaces/hostinger/.env.example`, `docs/COMPONENTS.md`, and provider listing version tables |
| Required operating-system package or Docker behavior | `ansible/roles/host/tasks/packages.yml` or another task under `ansible/roles/host/` |
| Bootstrap dependency needed before Ansible can run | Local `getting-started.sh` |
| New user input, environment variable, or validation | Local `getting-started.sh`, `ansible/group_vars/all.yml`, and `ansible/roles/preflight/` |
| Service start, pull, Compose, or readiness behavior | `ansible/roles/netbird/tasks/main.yml` |
| Public endpoint or post-install verification | `ansible/roles/post/tasks/main.yml` and `scripts/live-provider-test.sh` |
| Required firewall port or host security behavior | `ansible/roles/host/tasks/security.yml`, provider documentation, and live tests |
| Provider DNS behavior | `ansible/roles/dns/` and only the affected provider adapter |
| New install phase or changed role ordering | `getting-started.yml`; this should be uncommon |
| Hostinger application change | Change the shared Compose file, then regenerate the Hostinger artifact; never edit it independently |
| Marketplace-specific input or boot behavior | The corresponding directory under `marketplaces/` |

Upstream may introduce optional modes such as external reverse proxies,
NetBird Proxy, CrowdSec, agent-network-only operation, custom certificates, or
IP-only deployment. Do not automatically expand the marketplace product to
include them. Adding a new exposed port, privileged service, customer input,
secret, or billable dependency requires an explicit product and security
decision plus provider-documentation updates.

## 4. Preserve marketplace invariants

Every update must retain these properties unless a reviewed design change says
otherwise:

- One public FQDN with a trusted certificate
- TCP 80 and 443 plus UDP 3478 as the documented public application ports
- At least 2 GB RAM
- Pinned container image tags; never `latest`
- Persistent configuration, datastore, and ACME volumes
- Idempotent configuration initialization and installer reruns
- Authenticated API behavior and an embedded identity provider
- Limited administrator SSH and protected generated credentials
- UFW, Fail2ban, and Docker-aware host firewall on full-server adapters
- Provider tokens absent from images, logs, metadata, Compose files, and Git
- A single canonical Compose model shared by every applicable provider

If upstream deliberately changes one of these assumptions, update the
architecture, provider submission documents, publishing guide, and tests in
the same pull request.

## 5. Update versions and documentation

When a component changes, update all of the following that apply:

- `versions.env`
- `marketplaces/hostinger/.env.example`
- `docs/COMPONENTS.md`
- DigitalOcean and Hetzner Packer snapshot names
- Provider `SUBMISSION.md` software/version sections
- `PUBLISHING.md` release notes and readiness statements
- The baseline tag and checksum at the top of this file

Do not change this repository's `VERSION` merely because the NetBird server
version changed. `VERSION` is the marketplace bundle release. Increment it
when preparing a new immutable one-click release, following `PUBLISHING.md`.

## 6. Regenerate and run static tests

After translating the changes:

```bash
make sync
make validate
make release
git diff --check
git status --short
```

`make sync` copies the canonical Compose model to Hostinger. The generated
`marketplaces/hostinger/docker-compose.yml` must not be edited by hand.

Review the final diff for:

- Unpinned or `latest` images
- New ports not reflected in firewalls and provider instructions
- New secrets rendered into world-readable files or logs
- Removed health checks or weakened TLS verification
- Destructive behavior on existing persistent volumes
- Provider artifacts that no longer use the shared implementation

## 7. Run provider live tests

Follow `TESTS.md`. Keep live tests disabled while adding secrets and variables,
then run providers individually before selecting `all`. Use Let's Encrypt
staging during iteration and production only for the final release candidate.

At minimum, confirm:

- Exact DNS answers through two public resolvers
- Staging ACME/HTTPS during iteration; trusted production TLS for the release
  candidate; HTTP-to-HTTPS behavior in both modes
- Dashboard and OIDC discovery return HTTP 200
- An unauthenticated API request returns HTTP 401 or 403
- Management gRPC uses HTTP/2 and the relay accepts a WebSocket upgrade
- Long-running containers are healthy
- An external RFC 5389 binding succeeds over UDP 3478
- Limited-user SSH and root SSH policy are correct where applicable
- Installation is idempotent
- Services recover after a provider reboot
- Temporary servers, SSH keys, DNS records, and snapshots are verified absent

Do not advance the baseline in this file when a provider test is skipped. Note
any provider outage separately and complete the missing test before publishing.

## 8. Finish the update

After all checks pass:

1. Replace the baseline tag and SHA-256 at the top of this file.
2. Record the upstream comparison URL and any intentionally excluded features
   in the pull request or release notes.
3. Commit generated artifacts together with their canonical source.
4. Push the branch and require the ordinary validation workflow to pass.
5. Merge to `main`, create the marketplace release tag, and repeat the final
   provider-delivery tests required by `PUBLISHING.md`.

Never reuse or move an existing marketplace release tag. If a published
artifact changes, increment the bundle `VERSION`, create a new tag, rebuild
image-based providers, and submit a new provider release.

## Emergency upstream security changes

For a security fix, use the same checksum, translation, and validation steps.
Do not copy an unreviewed script directly into an image to save time. Prioritize
the affected provider tests, rotate any possibly exposed credentials, rebuild
all affected snapshots, and document which old artifacts or versions must be
withdrawn.
