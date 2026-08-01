# shellcheck shell=bash
# NetBird Hetzner snapshot first-login setup.

if [[ $- == *i* &&
      ${EUID:-$(id -u)} -eq 0 &&
      -t 0 &&
      ! -e /var/lib/netbird-one-click/complete &&
      ! -e /var/lib/netbird-one-click/provisioning &&
      -x /opt/netbird-one-clicks/getting-started.sh ]]; then
  printf '\nNetBird needs a public hostname and TLS email before it can start.\n'
  printf 'Point the hostname at this server before continuing.\n'
  printf 'Preflight completes before SSH or firewall policy changes.\n\n'
  /opt/netbird-one-clicks/getting-started.sh --provider hetzner
fi
