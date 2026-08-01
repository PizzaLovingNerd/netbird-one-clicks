#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly VENV_DIR="/opt/netbird-one-click-venv"
readonly LOG_FILE="/var/log/netbird-one-click.log"

NON_INTERACTIVE=false
PREPARE_IMAGE=false

fail() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

report_error() {
  local exit_code=$?
  printf '[error] NetBird installation failed near line %s (exit %s).\n' \
    "${BASH_LINENO[0]:-unknown}" "${exit_code}" >&2
  printf '[error] Review %s for details.\n' "${LOG_FILE}" >&2
  exit "${exit_code}"
}

retry() {
  local attempts=$1
  local delay=$2
  local count=1
  shift 2

  until "$@"; do
    if ((count >= attempts)); then
      return 1
    fi
    printf '[warning] Attempt %s/%s failed; retrying in %ss.\n' \
      "${count}" "${attempts}" "${delay}" >&2
    sleep "${delay}"
    count=$((count + 1))
  done
}

usage() {
  printf '%s\n' \
    'Usage: getting-started.sh [options]' \
    '' \
    'Options:' \
    '  --provider NAME       generic, linode, digitalocean, vultr, or hetzner' \
    '  --domain FQDN         public NetBird hostname' \
    '  --email ADDRESS       Let'\''s Encrypt email' \
    '  --acme-ca-server URL  official Let'\''s Encrypt directory URL' \
    '  --admin-user NAME     limited sudo username' \
    '  --dns-zone ZONE       provider DNS zone when using NETBIRD_DNS_TOKEN' \
    '  --keep-root-ssh       do not disable direct root SSH' \
    '  --non-interactive     fail instead of prompting for required values' \
    '  --prepare-image       install Ansible dependencies only' \
    '  --help                show this help'
}

prompt_value() {
  local variable_name=$1
  local prompt=$2
  local default_value=${3:-}
  local current_value=${!variable_name:-}
  local answer

  [[ -z ${current_value} ]] || return 0
  if [[ ${NON_INTERACTIVE} == true ]]; then
    [[ -n ${default_value} ]] || fail "${variable_name} is required."
    printf -v "${variable_name}" '%s' "${default_value}"
    export "${variable_name?}"
    return 0
  fi

  if [[ -n ${default_value} ]]; then
    read -r -p "${prompt} [${default_value}]: " answer </dev/tty
    answer="${answer:-${default_value}}"
  else
    read -r -p "${prompt}: " answer </dev/tty
  fi
  [[ -n ${answer} ]] || fail "${variable_name} is required."
  printf -v "${variable_name}" '%s' "${answer}"
  export "${variable_name?}"
}

install_bootstrap_dependencies() {
  export DEBIAN_FRONTEND=noninteractive

  retry 5 10 apt-get -o Acquire::Retries=5 update
  retry 5 10 apt-get \
    -o Acquire::Retries=5 \
    install -y \
    dnsutils \
    git \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv

  if [[ ! -x "${VENV_DIR}/bin/ansible-playbook" ]]; then
    python3 -m venv "${VENV_DIR}"
    retry 5 10 "${VENV_DIR}/bin/python" -m pip \
      install --retries 5 --timeout 30 --upgrade pip
    retry 5 10 "${VENV_DIR}/bin/python" -m pip \
      install --retries 5 --timeout 30 \
      -r "${SCRIPT_DIR}/requirements.txt"
  fi
}

collect_inputs() {
  MARKETPLACE_PROVIDER="${MARKETPLACE_PROVIDER:-generic}"
  NETBIRD_ADMIN_USER="${NETBIRD_ADMIN_USER:-netbirdadmin}"
  NETBIRD_DISABLE_ROOT_SSH="${NETBIRD_DISABLE_ROOT_SSH:-true}"
  NETBIRD_ACME_CA_SERVER="${NETBIRD_ACME_CA_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"
  NETBIRD_DNS_TOKEN="${NETBIRD_DNS_TOKEN:-}"
  NETBIRD_DNS_ZONE="${NETBIRD_DNS_ZONE:-}"

  prompt_value NETBIRD_FQDN "Public NetBird hostname"
  prompt_value NETBIRD_ACME_EMAIL "Let's Encrypt email"
  prompt_value NETBIRD_ADMIN_USER "Limited sudo username" "netbirdadmin"

  if [[ ${NON_INTERACTIVE} == false ]]; then
    local keep_root
    read -r -p "Disable direct root SSH after copying the provider key? [Y/n]: " \
      keep_root </dev/tty
    if [[ ${keep_root} =~ ^[Nn]$ ]]; then
      NETBIRD_DISABLE_ROOT_SSH=false
    fi
  fi

  if [[ ${NON_INTERACTIVE} == false &&
        -z ${NETBIRD_DNS_TOKEN} &&
        ${MARKETPLACE_PROVIDER} =~ ^(linode|digitalocean)$ ]]; then
    local automate_dns
    read -r -p "Configure the A record with the provider DNS API? [y/N]: " \
      automate_dns </dev/tty
    if [[ ${automate_dns} =~ ^[Yy]$ ]]; then
      read -r -s -p "Provider DNS API token: " NETBIRD_DNS_TOKEN </dev/tty
      printf '\n' >/dev/tty
      prompt_value NETBIRD_DNS_ZONE "Existing provider DNS zone"
    fi
  fi

  export MARKETPLACE_PROVIDER
  export NETBIRD_FQDN
  export NETBIRD_ACME_EMAIL
  export NETBIRD_ACME_CA_SERVER
  export NETBIRD_ADMIN_USER
  export NETBIRD_DISABLE_ROOT_SSH
  export NETBIRD_DNS_TOKEN
  export NETBIRD_DNS_ZONE
  export NETBIRD_INSTALLER_DIR="${SCRIPT_DIR}"
}

run_playbook() {
  cd "${SCRIPT_DIR}/ansible"
  "${VENV_DIR}/bin/ansible-playbook" \
    --inventory inventory/localhost.yml \
    ../getting-started.yml
}

while (($# > 0)); do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || fail "--provider requires a value."
      MARKETPLACE_PROVIDER=$2
      shift 2
      ;;
    --domain)
      [[ $# -ge 2 ]] || fail "--domain requires a value."
      NETBIRD_FQDN=$2
      shift 2
      ;;
    --email)
      [[ $# -ge 2 ]] || fail "--email requires a value."
      NETBIRD_ACME_EMAIL=$2
      shift 2
      ;;
    --acme-ca-server)
      [[ $# -ge 2 ]] || fail "--acme-ca-server requires a value."
      NETBIRD_ACME_CA_SERVER=$2
      shift 2
      ;;
    --admin-user)
      [[ $# -ge 2 ]] || fail "--admin-user requires a value."
      NETBIRD_ADMIN_USER=$2
      shift 2
      ;;
    --dns-zone)
      [[ $# -ge 2 ]] || fail "--dns-zone requires a value."
      NETBIRD_DNS_ZONE=$2
      shift 2
      ;;
    --keep-root-ssh)
      NETBIRD_DISABLE_ROOT_SSH=false
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --prepare-image)
      PREPARE_IMAGE=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

if [[ ${EUID} -ne 0 ]]; then
  fail "Run this installer as root."
fi

install -d -m 0750 "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1
trap report_error ERR

install_bootstrap_dependencies
if [[ ${PREPARE_IMAGE} == true ]]; then
  cd "${SCRIPT_DIR}/ansible"
  "${VENV_DIR}/bin/ansible-playbook" \
    --inventory inventory/localhost.yml \
    prepare-image.yml
  printf '[info] NetBird image dependencies are ready.\n'
  exit 0
fi

collect_inputs
run_playbook
printf '[info] NetBird installation complete.\n'
