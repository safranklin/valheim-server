#!/usr/bin/env bash
# Configure private DigitalOcean Spaces backups without placing S3 credentials in Git.
set -euo pipefail

server_host=${VALHEIM_HOST:?Set VALHEIM_HOST to the Droplet Tailscale IP or MagicDNS name.}
bucket=${1:-}
region=${SPACES_REGION:-nyc3}
retention_days=${SPACES_RETENTION_DAYS:-90}

if [[ ! $bucket =~ ^[a-z0-9][a-z0-9.-]{2,62}$ ]]; then
  echo 'Usage: VALHEIM_HOST=fartheim bash scripts/setup-spaces-backups.sh BUCKET-NAME' >&2
  echo 'Bucket names must be 3-63 lowercase letters, digits, dots, or hyphens.' >&2
  exit 2
fi
if [[ ! $retention_days =~ ^[1-9][0-9]*$ ]]; then
  echo 'SPACES_RETENTION_DAYS must be a positive whole number.' >&2
  exit 2
fi

read -r -s -p 'DigitalOcean Spaces access key ID: ' access_key
printf '\n'
read -r -s -p 'DigitalOcean Spaces secret key: ' secret_key
printf '\n'
if [[ -z $access_key || -z $secret_key ]]; then
  echo 'Both Spaces credentials are required; nothing changed.' >&2
  exit 1
fi

remote_dir="fartheim/worlds"
tmp_config=$(mktemp)
trap 'rm -f "$tmp_config"; unset access_key secret_key' EXIT
chmod 600 "$tmp_config"
cat >"$tmp_config" <<EOF
[spaces]
type = s3
provider = DigitalOcean
access_key_id = $access_key
secret_access_key = $secret_key
endpoint = ${region}.digitaloceanspaces.com
acl = private
EOF

ssh "root@$server_host" 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rclone'
ssh "root@$server_host" 'install -d -m 0700 /root/.config/rclone /var/log/valheim; install -d -m 0755 /opt/valheim/bin'
scp "$tmp_config" "root@$server_host:/root/.config/rclone/rclone.conf"
ssh "root@$server_host" 'chmod 600 /root/.config/rclone/rclone.conf'

ssh "root@$server_host" bash -s -- "$bucket" "$remote_dir" "$retention_days" <<'REMOTE'
bucket=$1
remote_prefix=$2
retention_days=$3
cat > /opt/valheim/bin/spaces-backup <<EOF
#!/usr/bin/env bash
set -euo pipefail

source_dir=/opt/valheim/config/backups
remote_dir='spaces:${bucket}/${remote_prefix}'
retention_days=${retention_days}
log_file=/var/log/valheim/spaces-backup.log

exec 9>/run/valheim-spaces-backup.lock
flock -n 9 || exit 0

latest=\$(find "\$source_dir" -maxdepth 1 -type f -name 'worlds-*.zip' -printf '%T@ %f\\n' | sort -n | tail -n 1 | awk '{print \$2}')
if [[ ! \$latest =~ ^worlds-[0-9]{8}-[0-9]{6}\\.zip$ ]]; then
  echo "No completed world archive found in \$source_dir" >&2
  exit 1
fi

rclone copy "\$source_dir" "\$remote_dir" --include 'worlds-*.zip' --checksum --transfers 1 --checkers 2 --log-file "\$log_file" --log-level INFO
local_hash=\$(sha256sum "\$source_dir/\$latest" | awk '{print \$1}')
remote_hash=\$(rclone cat "\$remote_dir/\$latest" | sha256sum | awk '{print \$1}')
if [[ \$local_hash != \$remote_hash ]]; then
  echo "SHA-256 verification failed for \$latest" >&2
  exit 1
fi
rclone delete "\$remote_dir" --include 'worlds-*.zip' --min-age "\${retention_days}d" --log-file "\$log_file" --log-level INFO
rclone rmdirs "\$remote_dir" --leave-root || true
echo "Uploaded and verified \$latest (sha256 \$local_hash)"
EOF
chmod 0755 /opt/valheim/bin/spaces-backup
cat > /etc/systemd/system/valheim-spaces-backup.service <<'EOF'
[Unit]
Description=Copy Valheim world archives to DigitalOcean Spaces
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/valheim/bin/spaces-backup
EOF
cat > /etc/systemd/system/valheim-spaces-backup.timer <<'EOF'
[Unit]
Description=Run the Valheim Spaces backup after the hourly archive

[Timer]
OnCalendar=*-*-* *:10:00
Persistent=true
RandomizedDelaySec=90

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now valheim-spaces-backup.timer
systemctl start valheim-spaces-backup.service
systemctl --no-pager --full status valheim-spaces-backup.service
systemctl --no-pager list-timers valheim-spaces-backup.timer
REMOTE

echo "Spaces backups are active: s3://${bucket}/${remote_dir}/"
