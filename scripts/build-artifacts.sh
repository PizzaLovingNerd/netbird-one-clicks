#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR

allow_dirty=false
run_validation=true
output_arg="build/releases"

fail() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: build-artifacts.sh [options]

Build deterministic, checksummed release packages for every supported target.
Cloud image packages contain the complete Packer build context; creating the
billable provider snapshots still requires the provider token and Packer.

Options:
  --output DIR       output parent directory (default: build/releases)
  --allow-dirty      allow packaging an uncommitted working tree
  --skip-validation do not run sync and full validation first
  --help             show this help

SOURCE_DATE_EPOCH may be set to control archive timestamps. By default the
timestamp of HEAD is used when Git is available.
EOF
}

while (($# > 0)); do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || fail '--output requires a directory.'
      output_arg=$2
      shift 2
      ;;
    --allow-dirty)
      allow_dirty=true
      shift
      ;;
    --skip-validation)
      run_validation=false
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

command -v tar >/dev/null || fail 'tar is required.'
command -v gzip >/dev/null || fail 'gzip is required.'
command -v sha256sum >/dev/null || fail 'sha256sum is required.'
command -v python3 >/dev/null || fail 'python3 is required.'

version="$(<"${ROOT_DIR}/VERSION")"
[[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "VERSION is not a publishable semantic version: ${version}"
readonly version
readonly release_ref="v${version}"
readonly archive_prefix="netbird-one-clicks-${version}"

if [[ ${output_arg} = /* ]]; then
  output_parent=${output_arg}
else
  output_parent="${ROOT_DIR}/${output_arg}"
fi
mkdir -p -- "${output_parent}"
output_parent="$(cd "${output_parent}" && pwd)"
readonly output_parent
readonly output_dir="${output_parent}/${release_ref}"
[[ ! -e ${output_dir} ]] \
  || fail "Output already exists: ${output_dir}"

if command -v git >/dev/null && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_available=true
  git_commit="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  default_epoch="$(git -C "${ROOT_DIR}" show -s --format=%ct HEAD)"
else
  git_available=false
  git_commit="unknown"
  default_epoch="$(stat -c %Y "${ROOT_DIR}/VERSION")"
fi
readonly git_available
readonly git_commit

source_date_epoch="${SOURCE_DATE_EPOCH:-${default_epoch}}"
[[ ${source_date_epoch} =~ ^[0-9]+$ ]] \
  || fail 'SOURCE_DATE_EPOCH must be a non-negative integer.'
readonly source_date_epoch

if [[ ${run_validation} == true ]]; then
  "${ROOT_DIR}/scripts/sync-marketplace-assets.sh"
  "${ROOT_DIR}/scripts/validate.sh" all
fi

if [[ ${git_available} == true ]]; then
  working_tree_dirty=false
  git_status="$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=all)"
  if [[ -n ${git_status} ]]; then
    working_tree_dirty=true
    if [[ ${allow_dirty} == false ]]; then
      fail 'The working tree is dirty; commit the release or use --allow-dirty for development builds.'
    fi
  fi
else
  working_tree_dirty="unknown"
fi
readonly working_tree_dirty

staging_dir="$(mktemp -d "${output_parent}/.artifacts.tmp.XXXXXX")"
readonly staging_dir
readonly package_stage="${staging_dir}/packages"
readonly artifact_stage="${staging_dir}/${release_ref}"
install -d -m 0755 "${package_stage}" "${artifact_stage}"

cleanup() {
  if [[ -n ${staging_dir:-} && -d ${staging_dir} &&
        ${staging_dir} == "${output_parent}/.artifacts.tmp."* ]]; then
    rm -rf -- "${staging_dir}"
  fi
}
trap cleanup EXIT

copy_paths() {
  local destination=$1
  local relative
  shift

  for relative in "$@"; do
    [[ -e ${ROOT_DIR}/${relative} ]] \
      || fail "Required artifact input is missing: ${relative}"
    install -d -m 0755 "${destination}/$(dirname "${relative}")"
    cp -a -- "${ROOT_DIR}/${relative}" "${destination}/${relative}"
  done
}

create_archive() {
  local package_name=$1
  local package_root=$2
  local archive_path="${artifact_stage}/${package_name}.tar.gz"

  tar \
    --sort=name \
    --format=posix \
    --pax-option=delete=atime,delete=ctime \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mtime="@${source_date_epoch}" \
    -C "$(dirname "${package_root}")" \
    -cf - "$(basename "${package_root}")" \
    | gzip -n >"${archive_path}"
  printf '[artifact] %s\n' "${archive_path}"
}

readonly -a runtime_paths=(
  ansible
  shared
  getting-started.sh
  getting-started.yml
  requirements.txt
  versions.env
  VERSION
  LICENSE
  README.md
)

readonly -a source_paths=(
  .ansible-lint
  .github
  .gitignore
  .yamllint
  CHANGELOG.md
  LICENSE
  Makefile
  PUBLISHING.md
  README.md
  TESTS.md
  UPDATING.md
  VERSION
  WRITEUP.md
  ansible
  docs
  getting-started.sh
  getting-started.yml
  marketplaces
  requirements-dev.txt
  requirements.txt
  scripts
  shared
  versions.env
)

package_root="${package_stage}/${archive_prefix}-source"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" "${source_paths[@]}"
create_archive "${archive_prefix}-source" "${package_root}"

package_root="${package_stage}/${archive_prefix}-generic-installer"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" "${runtime_paths[@]}"
create_archive "${archive_prefix}-generic-installer" "${package_root}"

akamai_root="${package_stage}/akamai-marketplace-submission"
"${ROOT_DIR}/scripts/package-linode-submission.sh" "${akamai_root}"
create_archive "${archive_prefix}-akamai-marketplace-submission" "${akamai_root}"

package_root="${package_stage}/${archive_prefix}-linode-stackscript"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" \
  LICENSE VERSION marketplaces/manifest.yml marketplaces/assets \
  marketplaces/linode/README.md marketplaces/linode/stackscript.sh \
  marketplaces/linode/submission/LISTING.md
create_archive "${archive_prefix}-linode-stackscript" "${package_root}"

package_root="${package_stage}/${archive_prefix}-digitalocean-image-build-context"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" "${runtime_paths[@]}" \
  marketplaces/manifest.yml marketplaces/assets marketplaces/digitalocean
create_archive "${archive_prefix}-digitalocean-image-build-context" "${package_root}"

package_root="${package_stage}/${archive_prefix}-vultr-marketplace-submission"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" \
  LICENSE VERSION marketplaces/manifest.yml marketplaces/assets \
  marketplaces/vultr
create_archive "${archive_prefix}-vultr-marketplace-submission" "${package_root}"

package_root="${package_stage}/${archive_prefix}-hostinger-marketplace-submission"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" \
  LICENSE VERSION marketplaces/manifest.yml marketplaces/assets \
  marketplaces/hostinger
compose_url="https://raw.githubusercontent.com/PizzaLovingNerd/netbird-one-clicks/${release_ref}/marketplaces/hostinger/docker-compose.yml"
encoded_url="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${compose_url}")"
{
  printf '# Deploy on Hostinger\n\n'
  printf 'Immutable Compose URL: `%s`\n\n' "${compose_url}"
  printf '[![Deploy on Hostinger](https://assets.hostinger.com/vps/deploy.svg)]'
  printf '(https://www.hostinger.com/docker-hosting?compose_url=%s)\n' "${encoded_url}"
} >"${package_root}/marketplaces/hostinger/DEPLOY.md"
create_archive "${archive_prefix}-hostinger-marketplace-submission" "${package_root}"

package_root="${package_stage}/${archive_prefix}-hetzner-image-build-context"
install -d -m 0755 "${package_root}"
copy_paths "${package_root}" "${runtime_paths[@]}" \
  marketplaces/manifest.yml marketplaces/assets marketplaces/hetzner
create_archive "${archive_prefix}-hetzner-image-build-context" "${package_root}"

(
  cd "${artifact_stage}"
  sha256sum -- *.tar.gz >SHA256SUMS
)

python3 - "${artifact_stage}" "${version}" "${release_ref}" \
  "${git_commit}" "${source_date_epoch}" "${working_tree_dirty}" <<'PY'
import hashlib
import json
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
version, release_ref, commit, epoch, dirty = sys.argv[2:]
descriptions = {
    "akamai-marketplace-submission": "Akamai marketplace-apps pull-request tree",
    "digitalocean-image-build-context": "DigitalOcean Packer snapshot build context",
    "generic-installer": "Generic shell and Ansible installer",
    "hetzner-image-build-context": "Hetzner Packer snapshot build context and review data",
    "hostinger-marketplace-submission": "Hostinger Compose, deploy button, listing, and artwork",
    "linode-stackscript": "Standalone Linode StackScript and listing data",
    "source": "Complete publishable source tree",
    "vultr-marketplace-submission": "Vultr Vendor Data, listing, and artwork",
}
artifacts = []
prefix = f"netbird-one-clicks-{version}-"
for path in sorted(directory.glob("*.tar.gz")):
    kind = path.name.removeprefix(prefix).removesuffix(".tar.gz")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    artifacts.append(
        {
            "description": descriptions[kind],
            "file": path.name,
            "sha256": digest,
            "size_bytes": path.stat().st_size,
        }
    )
manifest = {
    "schema_version": 1,
    "application": "netbird-one-clicks",
    "version": version,
    "release_ref": release_ref,
    "git_commit": commit,
    "working_tree_dirty": None if dirty == "unknown" else dirty == "true",
    "source_date_epoch": int(epoch),
    "artifacts": artifacts,
}
(directory / "release-manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

mv -- "${artifact_stage}" "${output_dir}"
printf '[pass] Release artifacts written to %s\n' "${output_dir}"
