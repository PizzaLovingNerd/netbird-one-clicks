#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

if [[ ${EUID} -ne 0 ]]; then
  printf '[error] Image cleanup must run as root.\n' >&2
  exit 1
fi

rm -rf -- /tmp/netbird-source
rm -f -- /root/.bash_history /root/.ssh/authorized_keys
rm -f -- /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

apt-get clean
rm -rf -- /var/lib/apt/lists/*

cloud-init clean --logs --machine-id --seed --configs all
rm -rf -- /run/cloud-init/* /var/lib/cloud/*

journalctl --flush
journalctl --rotate
journalctl --vacuum-time=1s
find /var/log -type f -exec truncate --size 0 {} +
find /var/log -type f -name '*.[1-9]' -delete
find /var/log -type f -name '*.gz' -delete

fstrim --all || true
sync
printf '[info] Hetzner image cleanup complete.\n'
