#!/usr/bin/env bash
set -euo pipefail

for required_command in curl sha256sum unzip install; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Missing required command: $required_command" >&2
    echo 'On Ubuntu, install prerequisites with: sudo apt-get install -y curl unzip coreutils' >&2
    exit 1
  fi
done

terraform_version=1.14.0
repository_root=$(cd "$(dirname "$0")/.." && pwd)
tools_dir="$repository_root/.tools"
archive_name="terraform_${terraform_version}_linux_amd64.zip"
release_base="https://releases.hashicorp.com/terraform/$terraform_version"
working_dir=$(mktemp -d)
trap 'rm -rf "$working_dir"' EXIT

mkdir -p "$tools_dir"
curl -fsSLo "$working_dir/$archive_name" "$release_base/$archive_name"
curl -fsSLo "$working_dir/SHA256SUMS" "$release_base/terraform_${terraform_version}_SHA256SUMS"

expected_hash=$(awk -v archive="$archive_name" '$2 == archive { print $1 }' "$working_dir/SHA256SUMS")
actual_hash=$(sha256sum "$working_dir/$archive_name" | awk '{ print $1 }')

if [[ ! $expected_hash =~ ^[a-f0-9]{64}$ ]] || [[ $actual_hash != "$expected_hash" ]]; then
  echo 'Terraform download checksum verification failed.' >&2
  exit 1
fi

unzip -q "$working_dir/$archive_name" -d "$working_dir"
install -m 0755 "$working_dir/terraform" "$tools_dir/terraform"
echo "Installed Terraform $terraform_version at $tools_dir/terraform"
