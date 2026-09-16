#!/usr/bin/env bash
set -euo pipefail

server_host=${VALHEIM_HOST:?Set VALHEIM_HOST to the Droplet Tailscale IP or MagicDNS name.}
ssh "root@$server_host" 'set -euo pipefail
systemctl --no-pager --full status valheim-spaces-backup.timer
systemctl --no-pager --full status valheim-spaces-backup.service || true
tail -n 40 /var/log/valheim/spaces-backup.log 2>/dev/null || true
'
