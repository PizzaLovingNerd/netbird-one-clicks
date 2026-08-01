#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly OUTPUT_DIR="${1:-${ROOT_DIR}/build/akamai-marketplace-submission}"
readonly APP_DIR="${OUTPUT_DIR}/apps/linode-marketplace-netbird"
readonly DEPLOY_DIR="${OUTPUT_DIR}/deployment_scripts/linode-marketplace-netbird"

if [[ -e ${OUTPUT_DIR} ]]; then
  printf '[error] Output already exists: %s\n' "${OUTPUT_DIR}" >&2
  exit 1
fi

install -d -m 0755 "${APP_DIR}" "${DEPLOY_DIR}"
cp -a -- \
  "${ROOT_DIR}/ansible" \
  "${ROOT_DIR}/shared" \
  "${APP_DIR}/"
cp -a -- \
  "${ROOT_DIR}/getting-started.sh" \
  "${ROOT_DIR}/getting-started.yml" \
  "${ROOT_DIR}/requirements.txt" \
  "${ROOT_DIR}/versions.env" \
  "${ROOT_DIR}/VERSION" \
  "${ROOT_DIR}/LICENSE" \
  "${APP_DIR}/"
cp -a -- \
  "${ROOT_DIR}/marketplaces/linode/submission/README.md" \
  "${ROOT_DIR}/marketplaces/linode/submission/DOCUMENTATION.md" \
  "${ROOT_DIR}/marketplaces/linode/submission/ansible.cfg" \
  "${ROOT_DIR}/marketplaces/linode/submission/collections.yml" \
  "${ROOT_DIR}/marketplaces/linode/submission/provision.yml" \
  "${ROOT_DIR}/marketplaces/linode/submission/site.yml" \
  "${APP_DIR}/"
cp -a -- \
  "${ROOT_DIR}/marketplaces/linode/submission/netbird-deploy.sh" \
  "${DEPLOY_DIR}/"
cp -a -- "${ROOT_DIR}/.ansible-lint" "${ROOT_DIR}/.yamllint" "${APP_DIR}/"
install -d -m 0755 "${APP_DIR}/assets/logos"
cp -a -- "${ROOT_DIR}/marketplaces/assets/"*.svg "${APP_DIR}/assets/logos/"

printf '[pass] Akamai submission tree written to %s\n' "${OUTPUT_DIR}"
