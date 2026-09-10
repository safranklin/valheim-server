#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server_ip=${VALHEIM_HOST:?Set VALHEIM_HOST to the Droplet Tailscale IPv4 address or MagicDNS name}
mkdir -p backups
# Download finished backup archives; the container rotates them hourly.
scp -r "root@$server_ip:/opt/valheim/config/backups/." backups/
echo 'Downloaded to backups/. Copy these to another device or backup service too.'
