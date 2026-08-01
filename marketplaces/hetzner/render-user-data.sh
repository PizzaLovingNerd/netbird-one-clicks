#!/usr/bin/env bash

set -Eeuo pipefail

domain=""
email=""
admin_user="netbirdadmin"
disable_root_ssh="true"

fail() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: render-user-data.sh --domain FQDN --email ADDRESS [options]' \
    '' \
    'Options:' \
    '  --admin-user NAME   limited sudo username (default: netbirdadmin)' \
    '  --keep-root-ssh     retain direct root SSH access' \
    '  --help              show this help'
}

while (($# > 0)); do
  case "$1" in
    --domain)
      [[ $# -ge 2 ]] || fail '--domain requires a value.'
      domain=$2
      shift 2
      ;;
    --email)
      [[ $# -ge 2 ]] || fail '--email requires a value.'
      email=$2
      shift 2
      ;;
    --admin-user)
      [[ $# -ge 2 ]] || fail '--admin-user requires a value.'
      admin_user=$2
      shift 2
      ;;
    --keep-root-ssh)
      disable_root_ssh="false"
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

[[ ${domain} =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] \
  || fail 'The domain must be a valid lower-case public hostname.'
[[ ${email} =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]] \
  || fail 'The email address is invalid.'
[[ ${admin_user} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
  || fail 'The administrator username is invalid.'

printf '%s\n' \
  '#cloud-config' \
  '' \
  'write_files:' \
  '  - path: /usr/local/sbin/netbird-hetzner-provision' \
  '    owner: root:root' \
  '    permissions: "0700"' \
  '    content: |' \
  '      #!/usr/bin/env bash' \
  '      set -Eeuo pipefail' \
  '      umask 077' \
  '      readonly state_dir=/var/lib/netbird-one-click' \
  '      install -d -m 0700 "${state_dir}"' \
  '      touch "${state_dir}/provisioning"' \
  '      trap '\''rm -f -- "${state_dir}/provisioning"'\'' EXIT' \
  "      export MARKETPLACE_PROVIDER=hetzner" \
  "      export NETBIRD_FQDN=${domain}" \
  "      export NETBIRD_ACME_EMAIL=${email}" \
  "      export NETBIRD_ADMIN_USER=${admin_user}" \
  "      export NETBIRD_DISABLE_ROOT_SSH=${disable_root_ssh}" \
  '      /opt/netbird-one-clicks/getting-started.sh --provider hetzner --non-interactive' \
  '' \
  'runcmd:' \
  '  - [/usr/local/sbin/netbird-hetzner-provision]' \
  '' \
  'final_message: "NetBird provisioning finished after $UPTIME seconds."'
