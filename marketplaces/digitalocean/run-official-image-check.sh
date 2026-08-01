#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly commit="b70878804ca27c01d5f5e882d26485defbaba210"
readonly expected_sha256="91ff2b1880439c97ccdc49554c5ed8901b89ef250c8ac5fffe52811c68abac49"
readonly script_path="/tmp/99-img-check.sh"

curl \
  --fail \
  --location \
  --proto '=https' \
  --retry 4 \
  --retry-all-errors \
  --silent \
  --show-error \
  --output "${script_path}" \
  "https://raw.githubusercontent.com/digitalocean/marketplace-partners/${commit}/scripts/99-img-check.sh"
printf '%s  %s\n' "${expected_sha256}" "${script_path}" \
  | sha256sum --check --strict

# The cleanup runs in the preceding Packer connection. This final connection
# can create a fresh forwarded-agent socket and new service log entries, so
# remove both immediately before running DigitalOcean's checker.
rm -rf /root/.ssh/agent
find /var/log -type f -exec truncate -s 0 {} +

bash "${script_path}"
