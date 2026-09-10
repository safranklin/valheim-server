#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
server_ip=$(terraform -chdir=infra output -raw server_ip)
mkdir -p backups
# Download finished backup archives; the container rotates them hourly.
scp -r "root@$server_ip:/opt/valheim/config/backups/." backups/
echo 'Downloaded to backups/. Copy these to another device or backup service too.'
