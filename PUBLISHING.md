# Publishing the NetBird one-clicks

This is the release and submission runbook for Akamai Cloud (Linode),
DigitalOcean, Vultr, Hostinger, and Hetzner Cloud. Provider guidance was
rechecked against official sources on 2026-07-31.

Run release candidates through the disabled-by-default live workflow in
`TESTS.md` before completing the provider steps below.

Marketplace approval cannot be guaranteed by repository checks. Vendor
enrollment, agreements, brand approval, portal access, screenshots, and human
review remain external provider actions.

## Current readiness

| Provider | Repository artifact | Live evidence | Publication route |
| --- | --- | --- | --- |
| Akamai Cloud / Linode | Ready for an Akamai submission-tree export | Ubuntu 26.04 development test passed; final submission must use Ubuntu 24.04 | Pull request to Akamai's `marketplace-apps` `develop` branch |
| DigitalOcean | Packer image and official cleanup/check pipeline ready | Ubuntu 26.04 image passed 8 checks, 0 warnings, 0 failures and passed a live deployment | Vendor Portal with a newly built snapshot ID |
| Vultr | Imageless Vendor Data and portal copy ready | Cloud deployment passed; final Marketplace metadata-variable path needs a private portal build | Verified Marketplace Vendor portal |
| Hostinger | Generated Compose file and Deploy button copy ready | Exact Compose model passed Docker Manager, TLS, health, STUN, and reboot tests | Self-published Deploy on Hostinger button |
| Hetzner | Packer image plus English/German review bundle ready | Ubuntu 24.04 snapshot and cloud-init deployment passed | Private snapshot only unless Hetzner grants a direct review |

The live reports in `build/` are historical evidence. Traefik and Alpine were
subsequently moved to security-patched releases, so the tagged release must be
tested once more through each provider's final delivery path before submission.

## Mandatory release gate

Do not submit any provider until every applicable item is complete.

- [ ] NetBird approves the repository's BSD 3-Clause license and the two SVG
  assets in `marketplaces/assets/`.
- [ ] `support@netbird.io` and
  `https://docs.netbird.io/help/netbird-support` are approved as Marketplace
  contacts.
- [ ] Current, redacted 800×500 login and dashboard screenshots are approved.
- [x] The repository is public at
  `https://github.com/PizzaLovingNerd/netbird-one-clicks`.
- [ ] Release tag `v0.1.0` exists and is protected against mutation.
- [ ] `make sync && make validate && make release` passes from a clean clone.
- [ ] Container and installer versions match `docs/COMPONENTS.md`.
- [ ] No token, private key, `.env` file, Packer log, cloud-init log, or live
  credential file is tracked. `build/` must remain ignored.
- [ ] Each final artifact passes DNS, trusted TLS, dashboard, OIDC, API auth,
  UDP 3478, limited-user SSH where applicable, repeat installation, and reboot
  persistence checks.
- [ ] The release notes describe every version and security change.

### Publish the immutable source release

Run these steps from a clean `main` checkout:

```bash
make sync
make validate
make release

git status --short
git add .
git commit -m "Release NetBird one-clicks v0.1.0"
git tag -s v0.1.0 -m "NetBird one-clicks v0.1.0"
git push origin main
git push origin v0.1.0
```

Verify both release consumers before building or submitting:

```bash
git ls-remote --exit-code --tags \
  https://github.com/PizzaLovingNerd/netbird-one-clicks.git refs/tags/v0.1.0

curl --fail --location \
  https://raw.githubusercontent.com/PizzaLovingNerd/netbird-one-clicks/v0.1.0/marketplaces/hostinger/docker-compose.yml \
  >/dev/null
```

Never change a published tag. Increment `VERSION`, update both provider
`ONECLICKS_REF` defaults, rebuild images, and submit a new release instead.

## Common listing data

- Product: **NetBird Self-Hosted**
- Release: **0.1.0**
- Website: https://netbird.io/
- Documentation: https://docs.netbird.io/
- Support: https://docs.netbird.io/help/netbird-support
- Support email: support@netbird.io
- Category: Security / Networking
- Minimum memory: 2 GB
- Minimum disk: 8 GB
- Required application ports: TCP 80 and 443; UDP 3478
- Brand colors: `#F68330` and `#F05252`
- Component and license inventory: `docs/COMPONENTS.md`

Use `marketplaces/assets/netbird-color.svg` and
`marketplaces/assets/netbird-white.svg` only after brand-owner approval.
Capture screenshots from the final release candidate without customer data,
public IPs, tokens, email addresses, or passwords.

## Akamai Cloud / Linode

Official guidance:

- [Marketplace development guidelines](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/docs/DEVELOPMENT.md)
- [Contribution and listing requirements](https://github.com/akamai-compute-marketplace/marketplace-apps/blob/main/docs/CONTRIBUTING.md)
- [StackScript UDF requirements](https://techdocs.akamai.com/cloud-computing/docs/write-a-custom-script-for-use-with-stackscripts)

Akamai currently accepts Ubuntu 24.04 LTS for One-Click submissions. Do not
select Ubuntu 26.04 even though the shared installer can support it elsewhere.

### Build the Akamai pull-request tree

```bash
make validate
./scripts/package-linode-submission.sh
```

The generated, ignored tree is:

```text
build/akamai-marketplace-submission/
  apps/linode-marketplace-netbird/
  deployment_scripts/linode-marketplace-netbird/netbird-deploy.sh
```

It packages the shared roles without maintaining a second tracked installer.
The submitted StackScript clones Akamai's Marketplace repository and supports
their `GH_USER` and `BRANCH` staging overrides.

### Submit

1. Fork `akamai-compute-marketplace/marketplace-apps`.
2. Create a feature branch from `develop`, not `main`.
3. Copy the two generated directories into the same paths in the fork.
4. Copy the approved login/dashboard screenshots into the app's `assets/`
   folder. The generated logo vectors are already under `assets/logos/`.
5. Review `marketplaces/linode/submission/LISTING.md`, `README.md`, and
   `DOCUMENTATION.md`. The listing description is within Akamai's 100–125 word
   range.
6. Run Akamai's ShellCheck, yamllint, ansible-lint, and deployment CI against
   Ubuntu 24.04.
7. Deploy the staging StackScript on a Shared CPU 2 GB plan with a real DNS
   name and account SSH key.
8. Confirm `/home/<admin-user>/.credentials` exists with mode `0600`, limited
   SSH works, root SSH follows the selected policy, and no unused billable
   resources remain.
9. Open a pull request against Akamai's `develop` branch and attach the listing
   data, screenshots, support details, and test evidence.

The generated administrator password is created on the target and protected
with Ansible `no_log`; no static initial secret exists in source for Ansible
Vault to encrypt. State that explicitly in the pull request if the reviewer
asks about the Vault recommendation.

## DigitalOcean

Official guidance:

- [Marketplace partner image tools and requirements](https://github.com/digitalocean/marketplace-partners)
- [Vendor guidelines and application](https://marketplace.digitalocean.com/vendors/guidelines-resources)
- [Marketplace overview](https://docs.digitalocean.com/products/marketplace/)

The official cleanup and checker are pinned to current upstream commit
`b70878804ca27c01d5f5e882d26485defbaba210` with verified hashes.

### Build the final snapshot

```bash
set -a
source /path/to/private-provider.env
set +a

export PACKER_PLUGIN_PATH="$PWD/.tools/packer-plugins"
packer init marketplaces/digitalocean/packer.pkr.hcl
packer build marketplaces/digitalocean/packer.pkr.hcl \
  | tee build/digitalocean-v0.1.0-packer.log

jq -r '.builds[-1].artifact_id' build/manifest.json
```

The final log must show a supported OS, active UFW, no pending security
updates, no root key/history, and **0 warnings / 0 failures**. Keep the
snapshot until DigitalOcean accepts or supersedes it.

### Test and submit

1. Create a Droplet from the final snapshot on a 2 GB plan with an account SSH
   key.
2. Point a test hostname at it and complete the first-root-login flow.
3. Run the mandatory release-gate checks and save a redacted report.
4. Delete the test Droplet, temporary key, and test DNS record; retain the
   submission snapshot.
5. Apply as a Marketplace Vendor if the team is not already enrolled. The
   official contact for missing Vendor Portal access is
   `one-clicks-team@digitalocean.com`.
6. Create a **Droplet 1-Click App** and copy the fields from
   `marketplaces/digitalocean/SUBMISSION.md`.
7. Enter the numeric snapshot ID from `build/manifest.json`, all software
   versions/licenses, release notes, support details, icon, and screenshots.
8. Submit for review through the Vendor Portal.

For later releases, DigitalOcean documents a Vendor API `PATCH` using the app
ID and a new team-owned snapshot ID. Do not automate the initial submission or
send a token to that endpoint until the Vendor Portal app exists.

## Vultr

Official guidance:

- [Vultr Marketplace reference guide](https://docs.vultr.com/platform/marketplace/reference-guide)

This release is scoped to Cloud Compute, not Bare Metal. The `vultr` kernel
argument is optional for cloud-only applications. Use Vultr's Ubuntu 24.04
image with its supported cloud-init build.

### Configure and publish

1. Become a verified Marketplace Vendor and accept the Publisher Agreement.
2. Create the application profile using
   `marketplaces/vultr/SUBMISSION.md`; leave **Repo URL** blank as instructed.
3. Create the three variables exactly as documented: `nb_domain`,
   `acme_email`, and optional `admin_user`. All comply with the 15-character,
   lowercase snake_case limit.
4. Paste the Readme and Application Instructions from `SUBMISSION.md`.
5. Upload the approved icon and the redacted 800×500 login/dashboard PNGs
   through Vultr's editor. External image URLs are not displayed.
6. Select **Build from Vendor Data**, choose Ubuntu 24.04, and paste
   `marketplaces/vultr/vendor-data.yml`.
7. Use the Marketplace 2 CPU / 2 GB / 8 GB build plan.
8. Use **Deploy Image** while the build is Not Live. Verify metadata values,
   temporary SSH blocking, exact DNS, trusted TLS, health, limited-user SSH,
   rerun behavior, and reboot recovery.
9. Set version `0.1.0`, choose **Publish Image**, then set the public URL slug
   and public visibility in Settings.
10. Submit the public application for Vultr review.

The Vendor Data clones the public `v0.1.0` tag. A private portal build cannot
pass until that tag is publicly reachable.

## Hostinger

Official guidance:

- [Deploy on Hostinger button](https://www.hostinger.com/support/deploy-on-hostinger-button/)
- [Docker Manager Compose deployment](https://www.hostinger.com/support/12040815-how-to-deploy-your-first-container-with-hostinger-docker-manager/)
- [Current Docker Catalog](https://www.hostinger.com/support/hostinger-docker-catalog-applications/)

Hostinger's documented public mechanism is self-publishing a button; there is
no documented third-party Docker Catalog submission form.

### Publish the button

```bash
compose_url='https://raw.githubusercontent.com/PizzaLovingNerd/netbird-one-clicks/v0.1.0/marketplaces/hostinger/docker-compose.yml'
encoded_url=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$compose_url")
printf 'https://www.hostinger.com/docker-hosting?compose_url=%s\n' "$encoded_url"
```

Use that URL with Hostinger's official button image as shown in
`marketplaces/hostinger/SUBMISSION.md`. Test the public button in a signed-out
browser through checkout and Docker Manager. Before deployment, provide
`NETBIRD_FQDN` and `NETBIRD_ACME_EMAIL`; then configure hPanel for TCP 80/443
and UDP 3478.

For curated catalog inclusion, contact Hostinger's partnership/product team
with `SUBMISSION.md`, the immutable Compose URL, test evidence, support
details, icon, and screenshots. Do not describe catalog inclusion as available
until Hostinger confirms it.

## Hetzner Cloud

Official guidance:

- [Hetzner Cloud Apps repository and contribution status](https://github.com/hetznercloud/apps)
- [Hetzner Packer builder](https://developer.hashicorp.com/packer/integrations/hetznercloud/hcloud/latest/components/builder/hcloud)
- [Hetzner metadata service](https://docs.hetzner.cloud/reference/cloud#metadata-service)

Hetzner currently states that it cannot accept suggestions for new apps. There
is therefore no valid public submission step today.

### Publish a private snapshot

```bash
set -a
source /path/to/private-provider.env
set +a
export HCLOUD_TOKEN="$HETZNER_TOKEN"

packer init marketplaces/hetzner/packer.pkr.hcl
packer build marketplaces/hetzner/packer.pkr.hcl \
  | tee build/hetzner-v0.1.0-packer.log

jq -r '.builds[-1].artifact_id' build/hetzner-manifest.json
```

Test the snapshot with credential-free user data from
`render-user-data.sh`, then repeat the mandatory release gate. Remove the test
server and temporary SSH key, but retain the approved private snapshot if it
is the distributable artifact. Snapshots remain billable.

### Prepare for a direct review or reopened submissions

The provider-style bundle is in `marketplaces/hetzner/submission/` and includes
`metadata.json`, English documentation, and German documentation. The
`os_id: 0` value is intentionally unresolved because Hetzner's internal app
build assigns the public base-image ID; do not present zero as a real image ID.
Provide the Packer source, tested snapshot ID, metadata, approved logos,
screenshots, component licenses, and live-test report to a named Hetzner
reviewer. Do not open a new-app pull request while the official repository says
new suggestions are closed.

## After acceptance

- Record the provider listing URL, app ID/slug, artifact ID, release date, and
  reviewer in the release notes.
- Remove superseded snapshots only after the provider confirms the replacement
  is active and rollback is no longer needed.
- Revoke temporary build and DNS credentials.
- Monitor NetBird, Dashboard, Traefik, Alpine, Docker, Ubuntu, Ansible, and
  provider requirements for security or support changes.
- Rebuild image marketplaces and repeat clean-cloud tests for every release;
  never update only the listing text while leaving an older image active.
