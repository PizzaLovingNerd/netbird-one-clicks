#!/bin/bash

# NetBird Akamai Cloud / Linode Marketplace StackScript

set -Eeuo pipefail
umask 077
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1

## NetBird settings
#<UDF name="domain" label="Existing DNS zone" example="example.com">
#<UDF name="subdomain" label="NetBird subdomain (use @ for the zone apex)" example="netbird" default="netbird">
#<UDF name="acme_email" label="Email address for Let's Encrypt" example="admin@example.com">
#<UDF name="token_password" label="Linode DNS API token (optional when DNS already points here)" default="">

## SSH settings
#<UDF name="user_name" label="Limited sudo username" default="netbirdadmin">
#<UDF name="disable_root" label="Disable root access over SSH?" oneOf="Yes,No" default="Yes">

readonly ONECLICKS_REPOSITORY="${ONECLICKS_REPOSITORY:-https://github.com/PizzaLovingNerd/netbird-one-clicks.git}"
readonly ONECLICKS_REF="${ONECLICKS_REF:-v0.1.0}"
readonly INSTALL_DIR="/opt/netbird-one-clicks"
readonly CLONE_DIR="/tmp/netbird-one-clicks.clone"

cleanup() {
  local exit_code=$?
  if [[ ${exit_code} -eq 0 && -d ${CLONE_DIR} ]]; then
    rm -rf -- "${CLONE_DIR}"
  fi
}

report_error() {
  local exit_code=$?
  printf '[error] StackScript failed near line %s (exit %s).\n' \
    "${BASH_LINENO[0]:-unknown}" "${exit_code}" >&2
  printf '[error] Review /var/log/stackscript.log.\n' >&2
  exit "${exit_code}"
}

trap cleanup EXIT
trap report_error ERR

if [[ ${EUID} -ne 0 ]]; then
  printf '[error] This StackScript must run as root.\n' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=5 update
apt-get -o Acquire::Retries=5 install -y ca-certificates git

if [[ -e ${INSTALL_DIR} || -e ${CLONE_DIR} ]]; then
  printf '[error] Refusing to overwrite an existing installer directory.\n' >&2
  exit 1
fi

git init "${CLONE_DIR}"
git -C "${CLONE_DIR}" remote add origin "${ONECLICKS_REPOSITORY}"
git -C "${CLONE_DIR}" fetch --depth 1 origin "${ONECLICKS_REF}"
git -C "${CLONE_DIR}" checkout --detach FETCH_HEAD
mv -- "${CLONE_DIR}" "${INSTALL_DIR}"

if [[ ${SUBDOMAIN} == "@" ]]; then
  NETBIRD_FQDN="${DOMAIN}"
else
  NETBIRD_FQDN="${SUBDOMAIN}.${DOMAIN}"
fi

export MARKETPLACE_PROVIDER=linode
export NETBIRD_FQDN
export NETBIRD_ACME_EMAIL="${ACME_EMAIL}"
export NETBIRD_ADMIN_USER="${USER_NAME}"
NETBIRD_DISABLE_ROOT_SSH="$(
  [[ ${DISABLE_ROOT} == "Yes" ]] && printf true || printf false
)"
export NETBIRD_DISABLE_ROOT_SSH
export NETBIRD_DNS_TOKEN="${TOKEN_PASSWORD}"
export NETBIRD_DNS_ZONE="${DOMAIN}"

"${INSTALL_DIR}/getting-started.sh" --provider linode --non-interactive

# Retain the release payload for supported reruns, but remove clone metadata
# that is not needed by the deployed service.
rm -rf -- "${INSTALL_DIR}/.git"
