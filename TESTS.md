# Testing the provider one-clicks

The repository has two intentionally separate GitHub Actions workflows:

- `Validate marketplace artifacts` runs on pull requests and pushes to `main`.
  It is offline, does not read provider secrets, and does not create resources.
- `Provider live tests` is manual-only and doubly disabled by default. It can
  create billable resources and must be enabled explicitly for each run.

The live workflow uses a unique `nb-<provider>-<run>-<attempt>` A record in a
DigitalOcean-managed DNS zone. It verifies public DNS, HTTP-to-HTTPS redirect,
HTTPS, the dashboard, OIDC discovery, the unauthenticated API boundary, an
external RFC 5389 UDP STUN binding, repeat deployment without secret rotation,
management gRPC over HTTP/2, relay WebSocket upgrade, container health, and
restart or reboot persistence. Image-based providers
also build their Packer snapshot from the checked-out commit. Disposable
resources and DNS records are deleted and polled until absent by an `EXIT`
trap; a cleanup failure fails the job.

## Safety model

Live jobs run only when all five conditions are true:

1. The workflow is started manually with **Run workflow**.
2. The selected Git ref is the `main` branch.
3. Repository variable `LIVE_PROVIDER_TESTS_ENABLED` is exactly `true`.
4. The `confirm_live_costs` checkbox is selected for that dispatch.
5. The `marketplace-live-tests` GitHub Environment grants approval.

An absent or false repository variable leaves every provider job skipped. The
workflow has no `push`, `pull_request`, or `schedule` trigger. One live workflow
runs at a time so that resource cleanup and account limits do not overlap.

Do not enable live tests for pull requests from forks. GitHub-hosted runner
addresses change; provider API allowlists must permit the runner, or the
workflow should be changed to a controlled self-hosted runner with a static
egress address.

Create the **marketplace-live-tests** Environment under **Settings →
Environments**. Add a required reviewer and limit deployment branches to
`main`. Store provider secrets in this Environment when possible. The workflow
exposes them only to the provider test step; checkout, dependency installation,
and artifact upload do not inherit provider credentials.

## Required GitHub Secrets

Add secrets under **Settings → Secrets and variables → Actions → Secrets**.
Never add the contents of a local `.env` file to the repository.

| Secret | Used by | Required access |
| --- | --- | --- |
| `DIGITALOCEAN_DNS_TOKEN` | Every job | Read/create/delete A records only in `TEST_DNS_ZONE`. |
| `DIGITALOCEAN_TOKEN` | DigitalOcean | Create/delete build Droplets, test Droplets, snapshots, actions, and temporary SSH keys. |
| `LINODE_TOKEN` | Linode | Create/read/delete Linodes and private StackScripts; boot and reboot the test Linode. |
| `VULTR_API_KEY` | Vultr | Create/read/reboot/delete instances and create/delete temporary SSH keys. The API allowlist must admit the runner. |
| `HOSTINGER_API_TOKEN` | Hostinger | Read the selected VPS, create/read/delete Docker Manager projects, read containers/actions, and restart the VPS. |
| `HETZNER_TOKEN` | Hetzner | Read/write access to the test project for servers, snapshots/images, actions, and SSH keys. |

Use dedicated test projects/accounts and the narrowest provider permissions
that cover the resources above. Rotate a token immediately if a workflow log
or artifact ever exposes it. GitHub masks registered secret values, but the
test script also avoids command tracing and never prints request bodies.

Official API references:

- [Akamai Cloud API](https://techdocs.akamai.com/linode-api/reference/api)
- [DigitalOcean API](https://docs.digitalocean.com/reference/api/)
- [Vultr API](https://www.vultr.com/api/)
- [Hostinger API](https://developers.hostinger.com/)
- [Hetzner Cloud API](https://docs.hetzner.cloud/)

## Required GitHub Variables

Add variables under **Settings → Secrets and variables → Actions → Variables**.

| Variable | Required | Example or default | Purpose |
| --- | --- | --- | --- |
| `LIVE_PROVIDER_TESTS_ENABLED` | Yes | `false` initially | Master safety switch. Change to `true` only after the remaining configuration is complete. |
| `TEST_DNS_ZONE` | Yes | `example.com` | Existing public zone hosted in DigitalOcean DNS. Tests create unique records beneath it. |
| `TEST_ACME_EMAIL` | Yes | `ci@example.com` | Address supplied to Let's Encrypt for test certificates. |
| `VULTR_MARKETPLACE_IMAGE_ID` | For Vultr | Provider-assigned image ID | ID of the current private, **Not Live** Marketplace image built from `marketplaces/vultr/vendor-data.yml`. |
| `HOSTINGER_VM_ID` | For Hostinger | Numeric VPS ID | Dedicated disposable Docker OS VPS used by Docker Manager tests. |

Optional location and size overrides have safe 2 GB defaults:

| Variable | Default |
| --- | --- |
| `LINODE_REGION` | `us-west` |
| `LINODE_TYPE` | `g6-standard-1` |
| `DIGITALOCEAN_REGION` | `nyc3` |
| `DIGITALOCEAN_SIZE` | `s-1vcpu-2gb` |
| `VULTR_REGION` | `lax` |
| `VULTR_PLAN` | `vc2-1c-2gb` |
| `HETZNER_LOCATION` | `fsn1` |
| `HETZNER_SERVER_TYPE` | `cx23` |

The selected plans must remain available to the test account and must satisfy
the one-click's 2 GB memory requirement.

## Provider preparation

### Akamai Cloud / Linode

No persistent provider artifact is needed. The job creates a private,
temporary StackScript from the checked-out `stackscript.sh`, injects the exact
GitHub commit, deploys Ubuntu 24.04, and removes both the Linode and StackScript.

### DigitalOcean

Use the separate DNS and compute secrets above. They may initially contain the
same token if the account cannot scope them separately, but separate narrowly
scoped tokens are preferred. The job runs the Packer build,
including DigitalOcean's official cleanup and image checker, creates a Droplet
from the resulting snapshot, completes first-login provisioning
noninteractively, reboots it, then deletes the Droplet, snapshot, SSH key, and
DNS record.

### Vultr

Create a private Marketplace application in the Vendor Portal, configure the
four variables `nb_domain`, `acme_email`, `admin_user`, and `acme_ca`, and
build a current **Not Live** image from `marketplaces/vultr/vendor-data.yml`.
Put its image ID
in `VULTR_MARKETPLACE_IMAGE_ID`. Rebuild this private image after changing the
vendor data or release tag; the API test deploys that image and supplies real
Marketplace `app_variables`, so a stale image tests stale code.

`acme_ca` is test-only and lets the private image use Let's Encrypt staging.
Do not add it to the public submission: public deployments omit it and safely
default to the production directory.

### Hostinger

Hostinger's public API can purchase a VPS but does not provide an equivalent
API operation to terminate the subscription safely. CI therefore never buys a
VPS. `HOSTINGER_VM_ID` must identify a dedicated, already-running Docker OS VPS
with no other workloads and with TCP 80/443 and UDP 3478 available. The job
deploys a uniquely named Docker Manager project, reboots the VPS, verifies the
deployment, and removes only that project. It never deletes or repurposes the
VPS subscription.

### Hetzner

The job builds a snapshot with Packer, creates a server from it with rendered
credential-free cloud-init, tests and reboots the server, then deletes the
server, snapshot, temporary SSH key, and DNS record. This tests the private
snapshot path because Hetzner does not currently accept new public app
suggestions.

## Enable and run

1. Add the provider secrets and common variables above while
   `LIVE_PROVIDER_TESTS_ENABLED` is absent or `false`.
2. Confirm the DigitalOcean zone is publicly delegated and the token can
   create and delete records in it.
3. Complete the Vultr and Hostinger provider preparation if either will run.
4. Change `LIVE_PROVIDER_TESTS_ENABLED` to `true`.
5. Open **Actions → Provider live tests → Run workflow** and select `main`.
6. Select one provider first. Select `confirm_live_costs`, then start the run.
7. Review the uploaded `*-live-test-<run-id>` artifact and each provider
   account after cleanup.
8. Once individual jobs pass, select `all` to run the five jobs in parallel.
9. Set `LIVE_PROVIDER_TESTS_ENABLED` back to `false` when live testing is not
   actively needed.

The dispatch defaults to `acme_environment=staging`. Staging certificates are
intentionally untrusted, so the test relaxes certificate trust only in that
mode while still exercising ACME issuance and HTTPS. Use `production` only for
the final release-candidate run; it performs normal trust verification and
consumes Let's Encrypt production issuance capacity. Avoid repeated production
`all` runs because five fresh hostnames are issued per run.

The CLI equivalent for a staging dispatch is:

```bash
gh workflow run provider-live-tests.yml \
  --ref main \
  -f provider=all \
  -f acme_environment=staging \
  -f confirm_live_costs=true
```

The repository variable still has to be `true`; the dispatch input cannot
bypass it. For the final release-candidate dispatch, change only
`acme_environment` to `production`.

## Cleanup and cost audit

Normal success and ordinary failures invoke automatic cleanup. Each known
resource deletion is polled until the provider reports it absent, and an API
or timeout failure makes the workflow fail. GitHub's hard
job cancellation, runner loss, provider outages, or an API permission error
can prevent an `EXIT` trap from completing. After every live run, search each
provider for names beginning with `netbird-ci-` or `nb-ci-`, and inspect the
DigitalOcean zone for `nb-*-<run>-<attempt>` records.

Pay particular attention to DigitalOcean and Hetzner snapshots because they
remain billable until deleted. Hostinger's dedicated VPS is intentionally
retained and continues to incur its normal subscription cost. Never use the
Hostinger job against a production VPS: it reboots the entire selected VM.

## Local static verification

The live workflow is not needed for ordinary development:

```bash
make validate
make release
bash -n scripts/live-provider-test.sh
```

These checks validate syntax and artifact alignment without reading provider
tokens or creating external resources. They do not replace a final live run
against each provider's delivery path.
