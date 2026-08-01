#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly MODE="${1:-all}"

run_syntax() {
  local file
  while IFS= read -r file; do
    bash -n "${file}"
  done < <(
    find \
      "${ROOT_DIR}" \
      -path "${ROOT_DIR}/.tools" -prune -o \
      -path "${ROOT_DIR}/.venv" -prune -o \
      -type f -name '*.sh' -print \
      | sort
  )
  printf '[pass] Bash syntax is valid.\n'

  if command -v shellcheck >/dev/null; then
    mapfile -t shell_files < <(
      find \
        "${ROOT_DIR}" \
        -path "${ROOT_DIR}/.tools" -prune -o \
        -path "${ROOT_DIR}/.venv" -prune -o \
        -type f -name '*.sh' -print \
        | sort
    )
    shellcheck --severity=warning "${shell_files[@]}"
    printf '[pass] ShellCheck passed.\n'
  else
    printf '[skip] ShellCheck is not installed.\n'
  fi
}

run_generated() {
  cmp \
    "${ROOT_DIR}/shared/docker-compose.yml" \
    "${ROOT_DIR}/marketplaces/hostinger/docker-compose.yml"
  printf '[pass] Generated Hostinger Compose artifact has no drift.\n'

  while IFS='=' read -r image_name image_value; do
    [[ ${image_name} == NETBIRD_*_IMAGE ]] || continue
    grep -Fq -- "${image_name}:-${image_value}" \
      "${ROOT_DIR}/shared/docker-compose.yml" || {
        printf '[error] %s is not aligned with shared Compose defaults.\n' \
          "${image_name}" >&2
        return 1
      }
    grep -Fq -- "${image_name}=${image_value}" \
      "${ROOT_DIR}/marketplaces/hostinger/.env.example" || {
        printf '[error] %s is not aligned with the Hostinger env example.\n' \
          "${image_name}" >&2
        return 1
      }
  done <"${ROOT_DIR}/versions.env"
  printf '[pass] Central image versions match Compose defaults.\n'
}

run_release() {
  local release_version
  local release_ref
  local netbird_server_image
  local netbird_server_version

  release_version="$(<"${ROOT_DIR}/VERSION")"
  release_ref="v${release_version}"

  grep -Fq -- "ONECLICKS_REF:-${release_ref}" \
    "${ROOT_DIR}/marketplaces/linode/stackscript.sh"
  grep -Fq -- "ONECLICKS_REF:-${release_ref}" \
    "${ROOT_DIR}/marketplaces/vultr/vendor-data.yml"

  netbird_server_image="$({
    grep '^NETBIRD_SERVER_IMAGE=' "${ROOT_DIR}/versions.env" || true
  } | cut -d= -f2-)"
  netbird_server_version="${netbird_server_image##*:}"
  [[ -n ${netbird_server_version} ]]
  grep -Fq -- "netbird-one-click-${netbird_server_version}-" \
    "${ROOT_DIR}/marketplaces/digitalocean/packer.pkr.hcl"
  grep -Fq -- "netbird-one-click-${netbird_server_version}-" \
    "${ROOT_DIR}/marketplaces/hetzner/packer.pkr.hcl"

  while IFS='=' read -r image_name image_value; do
    [[ ${image_name} == NETBIRD_*_IMAGE ]] || continue
    [[ ${image_value} == *:* ]]
    [[ ${image_value} != *:latest ]]
  done <"${ROOT_DIR}/versions.env"

  test -s "${ROOT_DIR}/LICENSE"
  test -s "${ROOT_DIR}/PUBLISHING.md"
  test -s "${ROOT_DIR}/docs/COMPONENTS.md"
  test -s "${ROOT_DIR}/marketplaces/linode/submission/README.md"
  test -s "${ROOT_DIR}/marketplaces/linode/submission/DOCUMENTATION.md"
  test -s "${ROOT_DIR}/marketplaces/digitalocean/SUBMISSION.md"
  test -s "${ROOT_DIR}/marketplaces/vultr/SUBMISSION.md"
  test -s "${ROOT_DIR}/marketplaces/hostinger/SUBMISSION.md"
  test -s "${ROOT_DIR}/marketplaces/hetzner/submission/README.md"
  test -s "${ROOT_DIR}/marketplaces/hetzner/submission/README.de.md"

  python3 -m json.tool \
    "${ROOT_DIR}/marketplaces/hetzner/submission/metadata.json" \
    >/dev/null

  if (( $(wc -c <"${ROOT_DIR}/marketplaces/hostinger/docker-compose.yml") > 8192 )); then
    printf '[error] Hostinger Compose artifact exceeds 8192 bytes.\n' >&2
    return 1
  fi

  printf '[pass] Release refs, image pins, and submission files are aligned.\n'
}

run_yaml() {
  python3 - "${ROOT_DIR}" <<'PY'
import pathlib
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:
    print("[skip] PyYAML is not installed.")
    raise SystemExit(0)

root = pathlib.Path(sys.argv[1])
files = sorted(
    path
    for path in root.rglob("*")
    if path.suffix in {".yml", ".yaml"}
    and ".tools" not in path.parts
    and ".venv" not in path.parts
    and "build" not in path.parts
)
for path in files:
    with path.open(encoding="utf-8") as stream:
        list(yaml.safe_load_all(stream))
print(f"[pass] Parsed {len(files)} YAML files.")

compose = yaml.safe_load((root / "shared/docker-compose.yml").read_text())
init_script = compose["services"]["netbird-config"]["command"][0]
with tempfile.TemporaryDirectory(prefix="netbird-config-test.") as temp_dir:
    init_script = init_script.replace("$$", "$").replace(
        "/config/", f"{temp_dir}/"
    )
    environment = {"NETBIRD_FQDN": "netbird.example.com"}
    subprocess.run(
        ["/bin/sh", "-ec", init_script],
        env=environment,
        check=True,
    )
    first = (pathlib.Path(temp_dir) / "config.yaml").read_text()
    config = yaml.safe_load(first)
    assert config["server"]["auth"]["issuer"] == (
        "https://netbird.example.com/oauth2"
    )
    assert len(config["server"]["authSecret"]) >= 40
    assert len(config["server"]["store"]["encryptionKey"]) >= 40
    subprocess.run(
        ["/bin/sh", "-ec", init_script],
        env=environment,
        check=True,
    )
    second = (pathlib.Path(temp_dir) / "config.yaml").read_text()
    assert first == second
print("[pass] Config init generated valid YAML and retained its secrets.")
PY

  if command -v yamllint >/dev/null; then
    yamllint -c "${ROOT_DIR}/.yamllint" "${ROOT_DIR}"
    printf '[pass] yamllint passed.\n'
  else
    printf '[skip] yamllint is not installed.\n'
  fi
}

run_ansible() {
  local ansible_command=""

  if command -v ansible-playbook >/dev/null; then
    ansible_command="$(command -v ansible-playbook)"
  elif [[ -x /opt/netbird-one-click-venv/bin/ansible-playbook ]]; then
    ansible_command="/opt/netbird-one-click-venv/bin/ansible-playbook"
  fi

  if [[ -z ${ansible_command} ]]; then
    printf '[skip] Ansible is not installed; run ./getting-started.sh --prepare-image on Ubuntu for the full check.\n'
    return 0
  fi

  (
    cd "${ROOT_DIR}/ansible"
    NETBIRD_INSTALLER_DIR="${ROOT_DIR}" \
    NETBIRD_FQDN="netbird.example.com" \
    NETBIRD_ACME_EMAIL="admin@example.com" \
      "${ansible_command}" \
        --inventory inventory/localhost.yml \
        --syntax-check \
        ../getting-started.yml
    "${ansible_command}" \
      --inventory inventory/localhost.yml \
      --syntax-check \
      prepare-image.yml
  )
  printf '[pass] Ansible syntax is valid.\n'

  if command -v ansible-lint >/dev/null; then
    (
      cd "${ROOT_DIR}/ansible"
      ansible-lint ../getting-started.yml prepare-image.yml
    )
    printf '[pass] ansible-lint passed.\n'
  else
    printf '[skip] ansible-lint is not installed.\n'
  fi
}

run_compose() {
  local -a compose_command=()

  if command -v docker >/dev/null &&
     docker compose version >/dev/null 2>&1; then
    compose_command=(docker compose)
  elif command -v docker-compose >/dev/null; then
    compose_command=(docker-compose)
  else
    printf '[skip] Docker Compose is not available.\n'
    return 0
  fi

  (
    cd "${ROOT_DIR}/shared"
    NETBIRD_FQDN="netbird.example.com" \
    NETBIRD_ACME_EMAIL="admin@example.com" \
      "${compose_command[@]}" config --quiet
  )
  printf '[pass] Docker Compose accepts the canonical model.\n'
}

run_packer() {
  if ! command -v packer >/dev/null; then
    printf '[skip] Packer is not installed.\n'
    return 0
  fi

  (
    cd "${ROOT_DIR}"
    packer fmt -check -diff marketplaces/digitalocean/packer.pkr.hcl
    packer fmt -check -diff marketplaces/hetzner/packer.pkr.hcl
    packer init marketplaces/digitalocean/packer.pkr.hcl
    packer init marketplaces/hetzner/packer.pkr.hcl
    DIGITALOCEAN_TOKEN=validation-only \
      packer validate marketplaces/digitalocean/packer.pkr.hcl
    HCLOUD_TOKEN=validation-only \
      packer validate marketplaces/hetzner/packer.pkr.hcl
  )
  printf '[pass] Provider Packer definitions are valid.\n'
}

case "${MODE}" in
  syntax)
    run_syntax
    ;;
  generated)
    run_generated
    ;;
  yaml)
    run_yaml
    ;;
  ansible)
    run_ansible
    ;;
  compose)
    run_compose
    ;;
  packer)
    run_packer
    ;;
  release)
    run_release
    ;;
  all)
    run_syntax
    run_generated
    run_release
    run_yaml
    run_ansible
    run_compose
    run_packer
    ;;
  *)
    printf '[error] Unknown validation mode: %s\n' "${MODE}" >&2
    exit 1
    ;;
esac
