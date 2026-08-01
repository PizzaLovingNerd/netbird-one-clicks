#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

readonly SOURCE_DIR="/tmp/netbird-source"
readonly INSTALL_DIR="/opt/netbird-one-clicks"

if [[ ${EUID} -ne 0 ]]; then
  printf '[error] Image installation must run as root.\n' >&2
  exit 1
fi

if [[ ! -x ${SOURCE_DIR}/getting-started.sh ]]; then
  printf '[error] Packer did not upload the repository payload.\n' >&2
  exit 1
fi

install -d -m 0755 "${INSTALL_DIR}"
cp -a -- "${SOURCE_DIR}/." "${INSTALL_DIR}/"
chown -R root:root "${INSTALL_DIR}"
find "${INSTALL_DIR}" -type d -exec chmod u+rwx,go+rx {} +
find "${INSTALL_DIR}" -type f -name '*.sh' -exec chmod 0755 {} +

"${INSTALL_DIR}/getting-started.sh" --prepare-image

install -m 0644 \
  "${INSTALL_DIR}/marketplaces/hetzner/first-login.sh" \
  /etc/profile.d/99-netbird-one-click.sh
install -m 0755 \
  "${INSTALL_DIR}/marketplaces/hetzner/motd" \
  /etc/update-motd.d/99-netbird-one-click

install -d -m 0700 /var/lib/netbird-one-click
install -d -m 0750 /var/log

systemctl enable docker.service containerd.service
printf '[info] Hetzner image payload installed.\n'
