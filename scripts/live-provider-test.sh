#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly PROVIDER="${1:-}"
readonly RUN_ID="${GITHUB_RUN_ID:-$(date +%s)}"
readonly RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
readonly ADMIN_USER="netbirdci"
readonly HOSTINGER_API_BASE="https://developers.hostinger.com/api/vps/v1"

case "${PROVIDER}" in
  linode|digitalocean|vultr|hostinger|hetzner) ;;
  *)
    printf 'Usage: %s {linode|digitalocean|vultr|hostinger|hetzner}\n' "$0" >&2
    exit 2
    ;;
esac

readonly OUTPUT_DIR="${ROOT_DIR}/build/live-tests/${PROVIDER}"
readonly LOG_FILE="${OUTPUT_DIR}/live-test.log"
readonly REPORT_FILE="${OUTPUT_DIR}/report.md"
readonly RECORD_LABEL="nb-${PROVIDER}-${RUN_ID}-${RUN_ATTEMPT}"

mkdir -p "${OUTPUT_DIR}"
exec > >(tee "${LOG_FILE}") 2>&1

DNS_RECORD_ID=""
INSTANCE_ID=""
SSH_KEY_ID=""
STACKSCRIPT_ID=""
SNAPSHOT_ID=""
HOSTINGER_PROJECT=""
HOSTINGER_PROJECT_CREATED=false
PUBLIC_IP=""
SSH_KEY_PATH=""
CLEANUP_FAILURES=0
TEST_BODY_COMPLETE=false
ACME_CA_SERVER=""
TLS_DESCRIPTION=""
declare -a HTTPS_CURL_ARGS=()

log() {
  printf '[%s] %s\n' "${PROVIDER}" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_env() {
  local name
  for name in "$@"; do
    [[ -n ${!name:-} ]] || fail "Required environment variable ${name} is empty."
  done
}

request_json() {
  local method=$1
  local url=$2
  local token=$3
  local body=${4:-}
  local -a args=(
    --fail-with-body
    --silent
    --show-error
    --request "${method}"
    --header "Authorization: Bearer ${token}"
    --header "Content-Type: application/json"
    "${url}"
  )

  # Retrying a create request after a lost response can duplicate billable
  # resources. Only retry read-only requests automatically.
  if [[ ${method} == GET ]]; then
    args+=(--retry 3 --retry-all-errors --retry-delay 2)
  fi
  if [[ -n ${body} ]]; then
    args+=(--data "${body}")
  fi
  curl "${args[@]}"
}

delete_resource() {
  local label=$1
  local url=$2
  local token=$3
  local response_code

  response_code="$(curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    --request DELETE \
    --header "Authorization: Bearer ${token}" \
    --header 'Content-Type: application/json' \
    "${url}" || true)"
  case "${response_code}" in
    2??|404) log "Deletion accepted for ${label}." ;;
    *)
      log "ERROR: cleanup of ${label} returned HTTP ${response_code}."
      return 1
      ;;
  esac
}

wait_for_resource_absent() {
  local label=$1
  local url=$2
  local token=$3
  local attempt
  local response_code

  for attempt in {1..60}; do
    response_code="$(curl \
      --silent \
      --show-error \
      --output /dev/null \
      --write-out '%{http_code}' \
      --header "Authorization: Bearer ${token}" \
      "${url}" || true)"
    if [[ ${response_code} == 404 ]]; then
      log "Verified ${label} is absent."
      return 0
    fi
    if [[ ! ${response_code} =~ ^2[0-9][0-9]$ ]]; then
      log "ERROR: verification of ${label} returned HTTP ${response_code}."
      return 1
    fi
    sleep 5
  done
  log "ERROR: ${label} still exists after cleanup timeout."
  return 1
}

cleanup_resource() {
  local label=$1
  local url=$2
  local token=$3

  if ! delete_resource "${label}" "${url}" "${token}" ||
     ! wait_for_resource_absent "${label}" "${url}" "${token}"; then
    CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
  fi
}

wait_for_hostinger_project_absent() {
  local attempt
  local response

  for attempt in {1..60}; do
    if ! response="$(request_json \
      GET \
      "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}/docker" \
      "${HOSTINGER_API_TOKEN}")"; then
      log "ERROR: Hostinger project-list cleanup verification failed."
      return 1
    fi
    if jq -e --arg name "${HOSTINGER_PROJECT}" \
      '[.[] | select(.name == $name)] | length == 0' \
      <<<"${response}" >/dev/null; then
      log "Verified Hostinger project ${HOSTINGER_PROJECT} is absent."
      return 0
    fi
    sleep 5
  done
  log "ERROR: Hostinger project ${HOSTINGER_PROJECT} still exists after cleanup timeout."
  return 1
}

cleanup() {
  local exit_code=$?
  trap - EXIT
  set +e

  case "${PROVIDER}" in
    linode)
      if [[ -n ${INSTANCE_ID} ]]; then
        cleanup_resource \
          "Linode ${INSTANCE_ID}" \
          "https://api.linode.com/v4/linode/instances/${INSTANCE_ID}" \
          "${LINODE_TOKEN}"
      fi
      if [[ -n ${STACKSCRIPT_ID} ]]; then
        cleanup_resource \
          "StackScript ${STACKSCRIPT_ID}" \
          "https://api.linode.com/v4/linode/stackscripts/${STACKSCRIPT_ID}" \
          "${LINODE_TOKEN}"
      fi
      ;;
    digitalocean)
      if [[ -n ${INSTANCE_ID} ]]; then
        cleanup_resource \
          "DigitalOcean Droplet ${INSTANCE_ID}" \
          "https://api.digitalocean.com/v2/droplets/${INSTANCE_ID}" \
          "${DIGITALOCEAN_TOKEN}"
      fi
      if [[ -n ${SNAPSHOT_ID} ]]; then
        cleanup_resource \
          "DigitalOcean snapshot ${SNAPSHOT_ID}" \
          "https://api.digitalocean.com/v2/images/${SNAPSHOT_ID}" \
          "${DIGITALOCEAN_TOKEN}"
      fi
      if [[ -n ${SSH_KEY_ID} ]]; then
        cleanup_resource \
          "DigitalOcean SSH key ${SSH_KEY_ID}" \
          "https://api.digitalocean.com/v2/account/keys/${SSH_KEY_ID}" \
          "${DIGITALOCEAN_TOKEN}"
      fi
      ;;
    vultr)
      if [[ -n ${INSTANCE_ID} ]]; then
        cleanup_resource \
          "Vultr instance ${INSTANCE_ID}" \
          "https://api.vultr.com/v2/instances/${INSTANCE_ID}" \
          "${VULTR_API_KEY}"
      fi
      if [[ -n ${SSH_KEY_ID} ]]; then
        cleanup_resource \
          "Vultr SSH key ${SSH_KEY_ID}" \
          "https://api.vultr.com/v2/ssh-keys/${SSH_KEY_ID}" \
          "${VULTR_API_KEY}"
      fi
      ;;
    hostinger)
      if [[ ${HOSTINGER_PROJECT_CREATED} == true ]]; then
        local hostinger_cleanup_response
        local hostinger_cleanup_action
        hostinger_cleanup_response="$(request_json \
          DELETE \
          "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}/docker/${HOSTINGER_PROJECT}/down" \
          "${HOSTINGER_API_TOKEN}" 2>/dev/null)"
        hostinger_cleanup_action="$(jq -r '.id // empty' <<<"${hostinger_cleanup_response}")"
        if [[ ! ${hostinger_cleanup_action} =~ ^[0-9]+$ ]] ||
           ! poll_hostinger_action "${hostinger_cleanup_action}" ||
           ! wait_for_hostinger_project_absent; then
          log "ERROR: Hostinger project cleanup could not be verified."
          CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
        else
          log "Verified Hostinger project cleanup completed."
        fi
      fi
      ;;
    hetzner)
      if [[ -n ${INSTANCE_ID} ]]; then
        cleanup_resource \
          "Hetzner server ${INSTANCE_ID}" \
          "https://api.hetzner.cloud/v1/servers/${INSTANCE_ID}" \
          "${HETZNER_TOKEN}"
      fi
      if [[ -n ${SNAPSHOT_ID} ]]; then
        cleanup_resource \
          "Hetzner snapshot ${SNAPSHOT_ID}" \
          "https://api.hetzner.cloud/v1/images/${SNAPSHOT_ID}" \
          "${HETZNER_TOKEN}"
      fi
      if [[ -n ${SSH_KEY_ID} ]]; then
        cleanup_resource \
          "Hetzner SSH key ${SSH_KEY_ID}" \
          "https://api.hetzner.cloud/v1/ssh_keys/${SSH_KEY_ID}" \
          "${HETZNER_TOKEN}"
      fi
      ;;
  esac

  if [[ -n ${DNS_RECORD_ID} ]]; then
    cleanup_resource \
      "DigitalOcean DNS record ${DNS_RECORD_ID}" \
      "https://api.digitalocean.com/v2/domains/${TEST_DNS_ZONE}/records/${DNS_RECORD_ID}" \
      "${DIGITALOCEAN_DNS_TOKEN}"
  fi
  if [[ -n ${SSH_KEY_PATH} ]]; then
    rm -f -- "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
  fi

  if ((CLEANUP_FAILURES > 0)); then
    exit_code=1
  fi
  write_report "${exit_code}" "${CLEANUP_FAILURES}"
  exit "${exit_code}"
}
trap cleanup EXIT

validate_common_configuration() {
  require_env DIGITALOCEAN_DNS_TOKEN TEST_DNS_ZONE TEST_ACME_EMAIL
  [[ ${TEST_DNS_ZONE} =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] \
    || fail "TEST_DNS_ZONE must be a lower-case public DNS zone."
  [[ ${TEST_ACME_EMAIL} =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]] \
    || fail "TEST_ACME_EMAIL is not a valid email address."
  [[ ${#RECORD_LABEL} -le 63 ]] || fail "Generated DNS label is too long."

  case "${TEST_ACME_ENVIRONMENT:-staging}" in
    staging)
      ACME_CA_SERVER=https://acme-staging-v02.api.letsencrypt.org/directory
      TLS_DESCRIPTION="Let's Encrypt staging TLS (untrusted by design)"
      HTTPS_CURL_ARGS=(--insecure)
      ;;
    production)
      ACME_CA_SERVER=https://acme-v02.api.letsencrypt.org/directory
      TLS_DESCRIPTION="trusted Let's Encrypt production TLS"
      HTTPS_CURL_ARGS=()
      ;;
    *) fail "TEST_ACME_ENVIRONMENT must be staging or production." ;;
  esac
}

create_ssh_key() {
  SSH_KEY_PATH="${RUNNER_TEMP:-/tmp}/netbird-${PROVIDER}-${RUN_ID}-${RUN_ATTEMPT}"
  rm -f -- "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
  ssh-keygen -q -t ed25519 -N '' -C "netbird-${PROVIDER}-ci" -f "${SSH_KEY_PATH}"
}

create_dns_record() {
  local existing
  local response

  existing="$(request_json \
    GET \
    "https://api.digitalocean.com/v2/domains/${TEST_DNS_ZONE}/records?type=A&name=${FQDN}" \
    "${DIGITALOCEAN_DNS_TOKEN}")"
  [[ $(jq '.domain_records | length' <<<"${existing}") -eq 0 ]] \
    || fail "Refusing to replace an existing DNS record for ${FQDN}."

  response="$(request_json \
    POST \
    "https://api.digitalocean.com/v2/domains/${TEST_DNS_ZONE}/records" \
    "${DIGITALOCEAN_DNS_TOKEN}" \
    "$(jq -n \
      --arg name "${RECORD_LABEL}" \
      --arg data "${PUBLIC_IP}" \
      '{type:"A", name:$name, data:$data, ttl:60}')")"
  DNS_RECORD_ID="$(jq -r '.domain_record.id' <<<"${response}")"
  [[ ${DNS_RECORD_ID} =~ ^[0-9]+$ ]] || fail "DigitalOcean did not return a DNS record ID."
  log "Created ${FQDN} -> ${PUBLIC_IP}."
}

wait_for_dns() {
  local attempt
  local resolver
  local answer

  for ((attempt = 1; attempt <= 90; attempt++)); do
    for resolver in 1.1.1.1 8.8.8.8; do
      answer="$(dig +short "@${resolver}" "${FQDN}" A | tail -1)"
      [[ ${answer} == "${PUBLIC_IP}" ]] || break
    done
    if [[ ${answer} == "${PUBLIC_IP}" ]]; then
      log "Public DNS resolves through both test resolvers."
      return 0
    fi
    sleep 10
  done
  fail "DNS did not converge to ${PUBLIC_IP}."
}

wait_for_https() {
  local attempt
  for attempt in {1..120}; do
    if curl "${HTTPS_CURL_ARGS[@]}" \
      --fail \
      --silent \
      --show-error \
      --connect-timeout 5 \
      --max-time 15 \
      "https://${FQDN}/oauth2/.well-known/openid-configuration" \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done
  fail "HTTPS did not become ready at ${FQDN}."
}

verify_public_endpoints() {
  local api_status
  local http_headers
  local http_location
  local http_status

  http_headers="$(curl \
    --silent \
    --show-error \
    --dump-header - \
    --output /dev/null \
    --max-time 15 \
    "http://${FQDN}/")"
  http_status="$(awk 'toupper($1) ~ /^HTTP\// {status=$2} END {print status}' <<<"${http_headers}")"
  http_location="$(awk 'BEGIN {IGNORECASE=1} /^location:/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' <<<"${http_headers}")"
  [[ ${http_status} =~ ^30[1278]$ && ${http_location} == "https://${FQDN}"* ]] \
    || fail "HTTP did not redirect to HTTPS (status ${http_status:-missing})."

  curl "${HTTPS_CURL_ARGS[@]}" --fail --silent --show-error "https://${FQDN}/" >/dev/null
  curl \
    "${HTTPS_CURL_ARGS[@]}" \
    --fail \
    --silent \
    --show-error \
    "https://${FQDN}/oauth2/.well-known/openid-configuration" \
    >/dev/null
  api_status="$(curl \
    "${HTTPS_CURL_ARGS[@]}" \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    "https://${FQDN}/api/users")"
  [[ ${api_status} == 401 || ${api_status} == 403 ]] \
    || fail "Unauthenticated API returned HTTP ${api_status}."
  log "HTTP redirect, dashboard, OIDC, authenticated API boundary, and ${TLS_DESCRIPTION} passed."
}

verify_public_stun() {
  python3 - "${PUBLIC_IP}" <<'PY'
import os
import socket
import struct
import sys

server = (sys.argv[1], 3478)
transaction_id = os.urandom(12)
request = struct.pack("!HHI12s", 0x0001, 0, 0x2112A442, transaction_id)

for _ in range(5):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(5)
        client.sendto(request, server)
        try:
            response, source = client.recvfrom(2048)
        except socket.timeout:
            continue
    if source[0] != server[0] or len(response) < 20:
        continue
    message_type, length, cookie, response_id = struct.unpack("!HHI12s", response[:20])
    if (
        message_type == 0x0101
        and cookie == 0x2112A442
        and response_id == transaction_id
        and len(response) >= 20 + length
    ):
        sys.exit(0)

raise SystemExit("No valid RFC 5389 STUN binding response received")
PY
  log "External UDP STUN binding passed."
  verify_public_protocol_routes
}

verify_public_protocol_routes() {
  local grpc_headers
  local grpc_status
  local grpc_type
  local relay_headers
  local relay_status

  grpc_headers="$(printf '\0\0\0\0\0' | curl \
    "${HTTPS_CURL_ARGS[@]}" \
    --http2 \
    --silent \
    --show-error \
    --request POST \
    --header 'Content-Type: application/grpc' \
    --data-binary @- \
    --dump-header - \
    --output /dev/null \
    --max-time 15 \
    "https://${FQDN}/management.ManagementService/GetServerKey")"
  grpc_status="$(awk 'toupper($1) ~ /^HTTP\// {status=$2} END {print status}' <<<"${grpc_headers}")"
  grpc_type="$(awk 'BEGIN {IGNORECASE=1} /^content-type:/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' <<<"${grpc_headers}")"
  [[ ${grpc_status} == 200 && ${grpc_type} == application/grpc* ]] \
    || fail "The public management gRPC route did not return gRPC over HTTP/2."

  relay_headers="$({ curl \
    "${HTTPS_CURL_ARGS[@]}" \
    --http1.1 \
    --silent \
    --request GET \
    --header 'Connection: Upgrade' \
    --header 'Upgrade: websocket' \
    --header 'Sec-WebSocket-Version: 13' \
    --header 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    --dump-header - \
    --output /dev/null \
    --max-time 3 \
    "https://${FQDN}/relay" || true; })"
  relay_status="$(awk 'toupper($1) ~ /^HTTP\// {status=$2} END {print status}' <<<"${relay_headers}")"
  [[ ${relay_status} == 101 ]] \
    || fail "The public relay route did not accept a WebSocket upgrade."
  log "External management gRPC and relay WebSocket routes passed."
}

wait_for_ssh() {
  local user=$1
  local attempt
  for attempt in {1..90}; do
    if ssh \
      -i "${SSH_KEY_PATH}" \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "${user}@${PUBLIC_IP}" true \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done
  fail "SSH for ${user} did not become ready."
}

ssh_command() {
  local user=$1
  shift
  ssh \
    -i "${SSH_KEY_PATH}" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${user}@${PUBLIC_IP}" \
    "$@"
}

verify_server_host() {
  local credentials_file=.netbird-access.txt
  local expected_compose_hash

  if [[ ${PROVIDER} == linode ]]; then
    credentials_file=.credentials
  fi
  expected_compose_hash="$(sha256sum "${ROOT_DIR}/shared/docker-compose.yml" | cut -d' ' -f1)"

  wait_for_ssh "${ADMIN_USER}"
  ssh_command "${ADMIN_USER}" bash -s -- \
    "${credentials_file}" "${expected_compose_hash}" <<'REMOTE'
set -Eeuo pipefail
credentials_file=$1
expected_compose_hash=$2
credentials_path="${HOME}/${credentials_file}"
test -s "${credentials_path}"
sudo_password="$(sed -n 's/^Sudo Password: //p' "${credentials_path}")"
test -n "${sudo_password}"
sudo_run() {
  printf '%s\n' "${sudo_password}" | sudo -S -p '' "$@"
}
sudo_run test -f /var/lib/netbird-one-click/complete
sudo_run systemctl is-active --quiet docker
sudo_run systemctl is-active --quiet fail2ban
sudo_run systemctl is-active --quiet netbird-docker-firewall
sudo_run sshd -T | grep -q '^permitrootlogin no$'
test "$(sudo_run sha256sum /opt/netbird/docker-compose.yml | cut -d' ' -f1)" = \
  "${expected_compose_hash}"
for container in netbird-traefik netbird-dashboard netbird-server; do
  test "$(sudo_run docker inspect --format '{{.State.Status}}' "${container}")" = running
  test "$(sudo_run docker inspect --format '{{.State.Health.Status}}' "${container}")" = healthy
done
sudo_run ss -lun | grep -Eq '(^|:)3478[[:space:]]'
REMOTE

  if ssh_command root true >/dev/null 2>&1; then
    fail "Direct root SSH is still available after provisioning."
  fi
  log "Limited-user SSH, host hardening, Compose hash, containers, and UDP 3478 passed."
}

verify_installer_idempotence() {
  local credentials_file=.netbird-access.txt

  if [[ ${PROVIDER} == linode ]]; then
    credentials_file=.credentials
  fi
  ssh_command "${ADMIN_USER}" bash -s -- \
    "${credentials_file}" "${PROVIDER}" "${FQDN}" "${TEST_ACME_EMAIL}" \
    "${ACME_CA_SERVER}" "${ADMIN_USER}" <<'REMOTE'
set -Eeuo pipefail
credentials_file=$1
provider=$2
fqdn=$3
acme_email=$4
acme_ca_server=$5
admin_user=$6
credentials_path="${HOME}/${credentials_file}"
sudo_password="$(sed -n 's/^Sudo Password: //p' "${credentials_path}")"
test -n "${sudo_password}"
sudo_run() {
  printf '%s\n' "${sudo_password}" | sudo -S -p '' "$@"
}
state_hash() {
  sudo_run sha256sum \
    /var/lib/netbird-one-click/sudo-password \
    /opt/netbird/.env \
    /var/lib/docker/volumes/netbird_config/_data/config.yaml
}
before="$(state_hash)"
sudo_run env \
  MARKETPLACE_PROVIDER="${provider}" \
  NETBIRD_FQDN="${fqdn}" \
  NETBIRD_ACME_EMAIL="${acme_email}" \
  NETBIRD_ACME_CA_SERVER="${acme_ca_server}" \
  NETBIRD_ADMIN_USER="${admin_user}" \
  NETBIRD_DISABLE_ROOT_SSH=true \
  /opt/netbird-one-clicks/getting-started.sh \
    --provider "${provider}" \
    --non-interactive
after="$(state_hash)"
test "${before}" = "${after}"
REMOTE
  log "A repeat installer run preserved credentials and NetBird state."
}

write_report() {
  local exit_code=${1:-1}
  local cleanup_failures=${2:-0}
  local result=failed

  if [[ ${exit_code} -eq 0 && ${TEST_BODY_COMPLETE} == true ]]; then
    result=passed
  fi
  cat >"${REPORT_FILE}" <<EOF
# ${PROVIDER} GitHub Actions live-test report

- Result: ${result}
- UTC time: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Commit: ${GITHUB_SHA:-local}
- Hostname: ${FQDN:-unavailable}
- Provider IPv4: ${PUBLIC_IP:-unavailable}
- DNS provider: DigitalOcean
- ACME environment: ${TEST_ACME_ENVIRONMENT:-staging}
- Cleanup: verified (${cleanup_failures} failures)
EOF
}

poll_hostinger_action() {
  local action_id=$1
  local attempt
  local response
  local action_state

  for attempt in {1..120}; do
    response="$(request_json \
      GET \
      "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}/actions/${action_id}" \
      "${HOSTINGER_API_TOKEN}")"
    action_state="$(jq -r '.state' <<<"${response}")"
    case "${action_state}" in
      success) return 0 ;;
      error)
        log "ERROR: Hostinger action ${action_id} failed."
        return 1
        ;;
    esac
    sleep 10
  done
  log "ERROR: Hostinger action ${action_id} timed out."
  return 1
}

deploy_hostinger_project() {
  local response
  local action_id

  # The name is deterministic, so cleanup can reconcile the project even if
  # the create request succeeds but its response is lost.
  HOSTINGER_PROJECT_CREATED=true
  response="$(request_json \
    POST \
    "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}/docker" \
    "${HOSTINGER_API_TOKEN}" \
    "$(jq -n \
      --arg project_name "${HOSTINGER_PROJECT}" \
      --rawfile content "${ROOT_DIR}/marketplaces/hostinger/docker-compose.yml" \
      --arg environment "NETBIRD_FQDN=${FQDN}\nNETBIRD_ACME_EMAIL=${TEST_ACME_EMAIL}\nNETBIRD_ACME_CA_SERVER=${ACME_CA_SERVER}" \
      '{project_name:$project_name, content:$content, environment:$environment}')")"
  action_id="$(jq -r '.id' <<<"${response}")"
  [[ ${action_id} =~ ^[0-9]+$ ]] || fail "Hostinger did not return a project action ID."
  poll_hostinger_action "${action_id}" || fail "Hostinger project deployment failed."
}

test_linode() {
  local script_file="${OUTPUT_DIR}/stackscript.sh"
  local response
  local root_password
  local instance_label="nb-ci-${RUN_ID}-${RUN_ATTEMPT}"
  local linode_status
  local attempt
  local repository=${ONECLICKS_TEST_REPOSITORY:-"https://github.com/${GITHUB_REPOSITORY}.git"}
  local release_ref=${ONECLICKS_TEST_REF:-${GITHUB_SHA}}

  require_env LINODE_TOKEN GITHUB_REPOSITORY GITHUB_SHA
  create_ssh_key

  awk \
    -v repository="${repository}" \
    -v release_ref="${release_ref}" \
    -v acme_ca_server="${ACME_CA_SERVER}" '
    NR == 2 {
      printf "export ONECLICKS_REPOSITORY=\047%s\047\n", repository
      printf "export ONECLICKS_REF=\047%s\047\n", release_ref
      printf "export NETBIRD_ACME_CA_SERVER=\047%s\047\n", acme_ca_server
    }
    { print }
  ' "${ROOT_DIR}/marketplaces/linode/stackscript.sh" >"${script_file}"
  chmod 0700 "${script_file}"

  response="$(request_json \
    POST \
    https://api.linode.com/v4/linode/stackscripts \
    "${LINODE_TOKEN}" \
    "$(jq -n \
      --arg label "netbird-ci-${RUN_ID}-${RUN_ATTEMPT}" \
      --rawfile script "${script_file}" \
      '{label:$label, description:"Disposable NetBird GitHub Actions test", images:["linode/ubuntu24.04"], is_public:false, script:$script}')")"
  STACKSCRIPT_ID="$(jq -r '.id' <<<"${response}")"
  [[ ${STACKSCRIPT_ID} =~ ^[0-9]+$ ]] || fail "Linode did not return a StackScript ID."

  root_password="A!a1$(openssl rand -hex 18)"
  response="$(request_json \
    POST \
    https://api.linode.com/v4/linode/instances \
    "${LINODE_TOKEN}" \
    "$(jq -n \
      --arg region "${LINODE_REGION:-us-west}" \
      --arg type "${LINODE_TYPE:-g6-standard-1}" \
      --arg label "${instance_label}" \
      --arg root_pass "${root_password}" \
      --arg ssh_key "$(<"${SSH_KEY_PATH}.pub")" \
      --arg domain "${TEST_DNS_ZONE}" \
      --arg subdomain "${RECORD_LABEL}" \
      --arg email "${TEST_ACME_EMAIL}" \
      --argjson stackscript_id "${STACKSCRIPT_ID}" \
      '{region:$region, type:$type, label:$label, image:"linode/ubuntu24.04", root_pass:$root_pass, authorized_keys:[$ssh_key], stackscript_id:$stackscript_id, stackscript_data:{domain:$domain, subdomain:$subdomain, acme_email:$email, token_password:"", user_name:"netbirdci", disable_root:"Yes"}, booted:true, tags:["netbird-oneclick-ci"]}')")"
  unset root_password
  INSTANCE_ID="$(jq -r '.id' <<<"${response}")"
  [[ ${INSTANCE_ID} =~ ^[0-9]+$ ]] || fail "Linode did not return an instance ID."

  for attempt in {1..90}; do
    response="$(request_json \
      GET \
      "https://api.linode.com/v4/linode/instances/${INSTANCE_ID}" \
      "${LINODE_TOKEN}")"
    linode_status="$(jq -r '.status' <<<"${response}")"
    PUBLIC_IP="$(jq -r '.ipv4[0] // empty' <<<"${response}")"
    if [[ ${linode_status} == running && -n ${PUBLIC_IP} ]]; then
      break
    fi
    sleep 10
  done
  [[ -n ${PUBLIC_IP} ]] || fail "Linode did not become ready."

  create_dns_record
  wait_for_dns
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
  verify_installer_idempotence
  verify_public_endpoints
  verify_public_stun
  verify_server_host

  request_json \
    POST \
    "https://api.linode.com/v4/linode/instances/${INSTANCE_ID}/reboot" \
    "${LINODE_TOKEN}" \
    '{}' >/dev/null
  sleep 20
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
}

test_digitalocean() {
  local response
  local key_name="netbird-ci-${RUN_ID}-${RUN_ATTEMPT}"
  local droplet_status
  local attempt
  local remote_command
  local manifest_file="${OUTPUT_DIR}/manifest.json"

  create_ssh_key
  export DIGITALOCEAN_TOKEN
  packer init "${ROOT_DIR}/marketplaces/digitalocean/packer.pkr.hcl"
  packer build \
    -color=false \
    -var "region=${DIGITALOCEAN_REGION:-nyc3}" \
    -var "size=${DIGITALOCEAN_SIZE:-s-1vcpu-2gb}" \
    -var "snapshot_name=netbird-ci-${RUN_ID}-${RUN_ATTEMPT}" \
    -var "manifest_output=${manifest_file}" \
    "${ROOT_DIR}/marketplaces/digitalocean/packer.pkr.hcl"
  SNAPSHOT_ID="$(jq -r '.builds[-1].artifact_id | split(":")[-1]' "${manifest_file}")"
  [[ ${SNAPSHOT_ID} =~ ^[0-9]+$ ]] || fail "Packer did not return a DigitalOcean snapshot ID."

  response="$(request_json \
    POST \
    https://api.digitalocean.com/v2/account/keys \
    "${DIGITALOCEAN_TOKEN}" \
    "$(jq -n \
      --arg name "${key_name}" \
      --arg public_key "$(<"${SSH_KEY_PATH}.pub")" \
      '{name:$name, public_key:$public_key}')")"
  SSH_KEY_ID="$(jq -r '.ssh_key.id' <<<"${response}")"
  [[ ${SSH_KEY_ID} =~ ^[0-9]+$ ]] || fail "DigitalOcean did not return an SSH key ID."

  response="$(request_json \
    POST \
    https://api.digitalocean.com/v2/droplets \
    "${DIGITALOCEAN_TOKEN}" \
    "$(jq -n \
      --arg name "${FQDN}" \
      --arg region "${DIGITALOCEAN_REGION:-nyc3}" \
      --arg size "${DIGITALOCEAN_SIZE:-s-1vcpu-2gb}" \
      --argjson image "${SNAPSHOT_ID}" \
      --argjson ssh_key "${SSH_KEY_ID}" \
      '{name:$name, region:$region, size:$size, image:$image, ssh_keys:[$ssh_key], backups:false, ipv6:false, monitoring:false}')")"
  INSTANCE_ID="$(jq -r '.droplet.id' <<<"${response}")"
  [[ ${INSTANCE_ID} =~ ^[0-9]+$ ]] || fail "DigitalOcean did not return a Droplet ID."

  for attempt in {1..90}; do
    response="$(request_json \
      GET \
      "https://api.digitalocean.com/v2/droplets/${INSTANCE_ID}" \
      "${DIGITALOCEAN_TOKEN}")"
    droplet_status="$(jq -r '.droplet.status' <<<"${response}")"
    PUBLIC_IP="$(jq -r '.droplet.networks.v4[]? | select(.type == "public") | .ip_address' <<<"${response}" | head -1)"
    if [[ ${droplet_status} == active && -n ${PUBLIC_IP} ]]; then
      break
    fi
    sleep 10
  done
  [[ -n ${PUBLIC_IP} ]] || fail "DigitalOcean Droplet did not become ready."

  create_dns_record
  wait_for_dns
  wait_for_ssh root
  printf -v remote_command \
    'cloud-init status --wait && env MARKETPLACE_PROVIDER=digitalocean NETBIRD_FQDN=%q NETBIRD_ACME_EMAIL=%q NETBIRD_ACME_CA_SERVER=%q NETBIRD_ADMIN_USER=%q NETBIRD_DISABLE_ROOT_SSH=true /opt/netbird-one-clicks/getting-started.sh --provider digitalocean --non-interactive' \
    "${FQDN}" "${TEST_ACME_EMAIL}" "${ACME_CA_SERVER}" "${ADMIN_USER}"
  ssh_command root "${remote_command}"
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
  verify_installer_idempotence
  verify_public_endpoints
  verify_public_stun
  verify_server_host

  request_json \
    POST \
    "https://api.digitalocean.com/v2/droplets/${INSTANCE_ID}/actions" \
    "${DIGITALOCEAN_TOKEN}" \
    '{"type":"reboot"}' >/dev/null
  sleep 20
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
}

test_vultr() {
  local response
  local instance_status
  local server_status
  local attempt
  local key_name="netbird-ci-${RUN_ID}-${RUN_ATTEMPT}"

  require_env VULTR_API_KEY VULTR_MARKETPLACE_IMAGE_ID
  create_ssh_key
  response="$(request_json \
    POST \
    https://api.vultr.com/v2/ssh-keys \
    "${VULTR_API_KEY}" \
    "$(jq -n \
      --arg name "${key_name}" \
      --arg ssh_key "$(<"${SSH_KEY_PATH}.pub")" \
      '{name:$name, ssh_key:$ssh_key}')")"
  SSH_KEY_ID="$(jq -r '.ssh_key.id' <<<"${response}")"
  [[ -n ${SSH_KEY_ID} && ${SSH_KEY_ID} != null ]] || fail "Vultr did not return an SSH key ID."

  response="$(request_json \
    POST \
    https://api.vultr.com/v2/instances \
    "${VULTR_API_KEY}" \
    "$(jq -n \
      --arg region "${VULTR_REGION:-lax}" \
      --arg plan "${VULTR_PLAN:-vc2-1c-2gb}" \
      --arg image_id "${VULTR_MARKETPLACE_IMAGE_ID}" \
      --arg label "netbird-ci-${RUN_ID}-${RUN_ATTEMPT}" \
      --arg hostname "${FQDN}" \
      --arg ssh_key "${SSH_KEY_ID}" \
      --arg domain "${FQDN}" \
      --arg email "${TEST_ACME_EMAIL}" \
      --arg acme_ca "${ACME_CA_SERVER}" \
      '{region:$region, plan:$plan, image_id:$image_id, label:$label, hostname:$hostname, ssh_key_ids:[$ssh_key], app_variables:{nb_domain:$domain, acme_email:$email, acme_ca:$acme_ca, admin_user:"netbirdci"}, user_scheme:"root", activation_email:false}')")"
  INSTANCE_ID="$(jq -r '.instance.id' <<<"${response}")"
  [[ -n ${INSTANCE_ID} && ${INSTANCE_ID} != null ]] || fail "Vultr did not return an instance ID."

  for attempt in {1..120}; do
    response="$(request_json \
      GET \
      "https://api.vultr.com/v2/instances/${INSTANCE_ID}" \
      "${VULTR_API_KEY}")"
    instance_status="$(jq -r '.instance.status' <<<"${response}")"
    server_status="$(jq -r '.instance.server_status' <<<"${response}")"
    PUBLIC_IP="$(jq -r '.instance.main_ip // empty' <<<"${response}")"
    if [[ ${instance_status} == active && ${server_status} == ok && -n ${PUBLIC_IP} ]]; then
      break
    fi
    sleep 10
  done
  [[ -n ${PUBLIC_IP} ]] || fail "Vultr instance did not become ready."

  create_dns_record
  wait_for_dns
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
  verify_installer_idempotence
  verify_public_endpoints
  verify_public_stun
  verify_server_host

  request_json \
    POST \
    "https://api.vultr.com/v2/instances/${INSTANCE_ID}/reboot" \
    "${VULTR_API_KEY}" \
    '{}' >/dev/null
  sleep 20
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
}

test_hostinger() {
  local response
  local action_id
  local unhealthy_count
  local vm_state

  require_env HOSTINGER_API_TOKEN HOSTINGER_VM_ID
  [[ ${HOSTINGER_VM_ID} =~ ^[0-9]+$ ]] || fail "HOSTINGER_VM_ID must be numeric."
  HOSTINGER_PROJECT="netbird-ci-${RUN_ID}-${RUN_ATTEMPT}"

  response="$(request_json \
    GET \
    "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}" \
    "${HOSTINGER_API_TOKEN}")"
  vm_state="$(jq -r '.state' <<<"${response}")"
  PUBLIC_IP="$(jq -r '.ipv4[0].address // empty' <<<"${response}")"
  [[ ${vm_state} == running && -n ${PUBLIC_IP} ]] \
    || fail "The Hostinger test VPS must be running with a public IPv4 address."

  create_dns_record
  wait_for_dns
  deploy_hostinger_project

  wait_for_https
  verify_public_endpoints
  verify_public_stun
  response="$(request_json \
    GET \
    "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}/docker/${HOSTINGER_PROJECT}/containers" \
    "${HOSTINGER_API_TOKEN}")"
  unhealthy_count="$(jq '[.[] | select(.name == "netbird-traefik" or .name == "netbird-dashboard" or .name == "netbird-server") | select(.state != "running" or .health != "healthy")] | length' <<<"${response}")"
  [[ ${unhealthy_count} -eq 0 ]] || fail "A Hostinger NetBird container is not healthy."
  [[ $(jq '[.[] | select(.name == "netbird-traefik" or .name == "netbird-dashboard" or .name == "netbird-server")] | length' <<<"${response}") -eq 3 ]] \
    || fail "Hostinger did not report all three long-running containers."

  deploy_hostinger_project
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  log "A repeat Hostinger project deployment passed."

  response="$(request_json \
    POST \
    "${HOSTINGER_API_BASE}/virtual-machines/${HOSTINGER_VM_ID}/restart" \
    "${HOSTINGER_API_TOKEN}" \
    '{}')"
  action_id="$(jq -r '.id' <<<"${response}")"
  [[ ${action_id} =~ ^[0-9]+$ ]] || fail "Hostinger did not return a reboot action ID."
  poll_hostinger_action "${action_id}" || fail "Hostinger reboot failed."
  sleep 20
  wait_for_https
  verify_public_endpoints
  verify_public_stun
}

test_hetzner() {
  local response
  local server_status
  local attempt
  local manifest_file="${OUTPUT_DIR}/manifest.json"
  local user_data_file="${OUTPUT_DIR}/user-data.yml"
  local key_name="netbird-ci-${RUN_ID}-${RUN_ATTEMPT}"

  require_env HETZNER_TOKEN
  create_ssh_key
  export HCLOUD_TOKEN="${HETZNER_TOKEN}"
  packer init "${ROOT_DIR}/marketplaces/hetzner/packer.pkr.hcl"
  packer build \
    -color=false \
    -var "location=${HETZNER_LOCATION:-fsn1}" \
    -var "server_type=${HETZNER_SERVER_TYPE:-cx23}" \
    -var "snapshot_name=netbird-ci-${RUN_ID}-${RUN_ATTEMPT}" \
    -var "manifest_output=${manifest_file}" \
    "${ROOT_DIR}/marketplaces/hetzner/packer.pkr.hcl"
  SNAPSHOT_ID="$(jq -r '.builds[-1].artifact_id | split(":")[-1]' "${manifest_file}")"
  [[ ${SNAPSHOT_ID} =~ ^[0-9]+$ ]] || fail "Packer did not return a Hetzner snapshot ID."

  response="$(request_json \
    POST \
    https://api.hetzner.cloud/v1/ssh_keys \
    "${HETZNER_TOKEN}" \
    "$(jq -n \
      --arg name "${key_name}" \
      --arg public_key "$(<"${SSH_KEY_PATH}.pub")" \
      '{name:$name, public_key:$public_key}')")"
  SSH_KEY_ID="$(jq -r '.ssh_key.id' <<<"${response}")"
  [[ ${SSH_KEY_ID} =~ ^[0-9]+$ ]] || fail "Hetzner did not return an SSH key ID."

  "${ROOT_DIR}/marketplaces/hetzner/render-user-data.sh" \
    --domain "${FQDN}" \
    --email "${TEST_ACME_EMAIL}" \
    --acme-ca-server "${ACME_CA_SERVER}" \
    --admin-user "${ADMIN_USER}" \
    >"${user_data_file}"
  response="$(request_json \
    POST \
    https://api.hetzner.cloud/v1/servers \
    "${HETZNER_TOKEN}" \
    "$(jq -n \
      --arg name "netbird-ci-${RUN_ID}-${RUN_ATTEMPT}" \
      --arg server_type "${HETZNER_SERVER_TYPE:-cx23}" \
      --arg location "${HETZNER_LOCATION:-fsn1}" \
      --arg image "${SNAPSHOT_ID}" \
      --argjson ssh_key "${SSH_KEY_ID}" \
      --rawfile user_data "${user_data_file}" \
      '{name:$name, server_type:$server_type, location:$location, image:$image, ssh_keys:[$ssh_key], user_data:$user_data, public_net:{enable_ipv4:true, enable_ipv6:false}, labels:{application:"netbird", purpose:"github-actions-test"}}')")"
  INSTANCE_ID="$(jq -r '.server.id' <<<"${response}")"
  [[ ${INSTANCE_ID} =~ ^[0-9]+$ ]] || fail "Hetzner did not return a server ID."

  for attempt in {1..90}; do
    response="$(request_json \
      GET \
      "https://api.hetzner.cloud/v1/servers/${INSTANCE_ID}" \
      "${HETZNER_TOKEN}")"
    server_status="$(jq -r '.server.status' <<<"${response}")"
    PUBLIC_IP="$(jq -r '.server.public_net.ipv4.ip // empty' <<<"${response}")"
    if [[ ${server_status} == running && -n ${PUBLIC_IP} ]]; then
      break
    fi
    sleep 10
  done
  [[ -n ${PUBLIC_IP} ]] || fail "Hetzner server did not become ready."

  create_dns_record
  wait_for_dns
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
  verify_installer_idempotence
  verify_public_endpoints
  verify_public_stun
  verify_server_host

  request_json \
    POST \
    "https://api.hetzner.cloud/v1/servers/${INSTANCE_ID}/actions/reboot" \
    "${HETZNER_TOKEN}" \
    '{}' >/dev/null
  sleep 20
  wait_for_https
  verify_public_endpoints
  verify_public_stun
  verify_server_host
}

validate_common_configuration
readonly FQDN="${RECORD_LABEL}.${TEST_DNS_ZONE}"
log "Starting disabled-by-default live test for ${FQDN}."

case "${PROVIDER}" in
  linode) test_linode ;;
  digitalocean) test_digitalocean ;;
  vultr) test_vultr ;;
  hostinger) test_hostinger ;;
  hetzner) test_hetzner ;;
esac

TEST_BODY_COMPLETE=true
log "Live test passed."
