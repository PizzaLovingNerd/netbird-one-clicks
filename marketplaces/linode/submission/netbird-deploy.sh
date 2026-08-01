#!/bin/bash

# NetBird Akamai Cloud Marketplace deployment StackScript.

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

readonly github_user="${GH_USER:-akamai-compute-marketplace}"
readonly branch="${BRANCH:-main}"
readonly repository="https://github.com/${github_user}/marketplace-apps.git"
readonly work_dir="/tmp/marketplace-apps"
readonly app_path="apps/linode-marketplace-netbird"
readonly install_dir="/opt/netbird-one-clicks"

cleanup() {
  local exit_code=$?
  rm -rf -- "${work_dir}"
  exit "${exit_code}"
}

report_error() {
  local exit_code=$?
  printf '[error] NetBird deployment failed near line %s (exit %s).\n' \
    "${BASH_LINENO[0]:-unknown}" "${exit_code}" >&2
  printf '[error] Review /var/log/stackscript.log.\n' >&2
  exit "${exit_code}"
}

trap cleanup EXIT
trap report_error ERR

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=5 update
apt-get -o Acquire::Retries=5 install -y ca-certificates git

git clone --depth 1 --branch "${branch}" -- "${repository}" "${work_dir}"
[[ -x ${work_dir}/${app_path}/getting-started.sh ]]
[[ ! -e ${install_dir} ]]
install -d -m 0755 "${install_dir}"
cp -a -- "${work_dir}/${app_path}/." "${install_dir}/"
chown -R root:root "${install_dir}"

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

"${install_dir}/getting-started.sh" --provider linode --non-interactive
