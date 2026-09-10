#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f .env ]] || grep -q 'REPLACE_WITH' .env; then
  echo 'Copy .env.example to .env and set your server password first.' >&2
  exit 1
fi
server_ip=$(terraform -chdir=infra output -raw server_ip)
ssh "root@$server_ip" 'cloud-init status --wait >/dev/null'
scp compose.yaml "root@$server_ip:/opt/valheim/compose.yaml"
# Stream the secret into a restricted file; never put it in Terraform state.
ssh "root@$server_ip" 'umask 077; cat > /opt/valheim/.env' < .env
ssh "root@$server_ip" 'cd /opt/valheim && docker compose config --quiet && docker compose pull && docker compose up -d'
echo "Deployed. View logs with: ssh root@$server_ip 'cd /opt/valheim && docker compose logs --tail=100 -f'"
