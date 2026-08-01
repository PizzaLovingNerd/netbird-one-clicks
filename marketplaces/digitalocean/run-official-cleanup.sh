#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly commit="b70878804ca27c01d5f5e882d26485defbaba210"
readonly expected_sha256="5e2fe7ce30892a26ed2731238d9f26c40ae8b1084b070ce095f3b99ab1a2cc81"
readonly script_path="/tmp/90-cleanup.sh"

curl \
  --fail \
  --location \
  --proto '=https' \
  --retry 4 \
  --retry-all-errors \
  --silent \
  --show-error \
  --output "${script_path}" \
  "https://raw.githubusercontent.com/digitalocean/marketplace-partners/${commit}/scripts/90-cleanup.sh"
printf '%s  %s\n' "${expected_sha256}" "${script_path}" \
  | sha256sum --check --strict

# DigitalOcean's cleanup deliberately fills the free filesystem with zeros.
# Keep Fail2ban from writing its SQLite state while the disk is full. The
# runtime-only mask disappears on the next boot, and the service remains
# persistently enabled for customer Droplets.
systemctl mask --runtime --now fail2ban.service

bash "${script_path}"
