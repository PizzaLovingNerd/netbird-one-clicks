#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly CANONICAL_COMPOSE="${ROOT_DIR}/shared/docker-compose.yml"
readonly HOSTINGER_COMPOSE="${ROOT_DIR}/marketplaces/hostinger/docker-compose.yml"

cp -- "${CANONICAL_COMPOSE}" "${HOSTINGER_COMPOSE}"
printf '[sync] Hostinger Compose artifact updated from the canonical model.\n'
