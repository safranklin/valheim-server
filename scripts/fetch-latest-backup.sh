#!/usr/bin/env bash
set -euo pipefail

server_host=${VALHEIM_HOST:-100.88.224.24}
backup_dir=${VALHEIM_BACKUP_DIR:-"$HOME/dev/ValheimBackups"}
remote_dir=/opt/valheim/config/backups

latest_backup=$(ssh "root@$server_host" "find '$remote_dir' -maxdepth 1 -type f -name 'worlds-*.zip' -printf '%T@ %f\\n' | sort -n | tail -n 1 | awk '{print \$2}'")

if [[ ! $latest_backup =~ ^worlds-[0-9]{8}-[0-9]{6}\.zip$ ]]; then
  echo 'Could not identify a valid completed backup on the server.' >&2
  exit 1
fi

remote_hash=$(ssh "root@$server_host" "sha256sum '$remote_dir/$latest_backup' | awk '{print \$1}'")
if [[ ! $remote_hash =~ ^[a-f0-9]{64}$ ]]; then
  echo 'Could not read a valid SHA-256 hash from the server.' >&2
  exit 1
fi

mkdir -p "$backup_dir"
destination="$backup_dir/$latest_backup"

if [[ -e $destination ]]; then
  local_hash=$(sha256sum "$destination" | awk '{print $1}')
  if [[ $local_hash == "$remote_hash" ]]; then
    echo "Already present and verified: $destination"
    exit 0
  fi
  echo "Refusing to overwrite a different local file: $destination" >&2
  exit 1
fi

temporary_file=$(mktemp "$backup_dir/.${latest_backup}.partial.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT

scp "root@$server_host:$remote_dir/$latest_backup" "$temporary_file"
local_hash=$(sha256sum "$temporary_file" | awk '{print $1}')

if [[ $local_hash != "$remote_hash" ]]; then
  echo 'SHA-256 verification failed; the incomplete download was removed.' >&2
  exit 1
fi

mv "$temporary_file" "$destination"
trap - EXIT
echo "Downloaded and verified: $destination"
