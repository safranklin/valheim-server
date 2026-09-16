# Cold start guide: WSL to Valheim

This guide rebuilds the infrastructure and server configuration from an empty Ubuntu WSL 2 installation. It creates one DigitalOcean Droplet in New York, uses Tailscale for private administration, runs Valheim in Docker, stores the game password outside Git, and publishes the game’s UDP ports.

It does **not** restore an existing world. To migrate an existing world, first obtain and verify an archive with `scripts/fetch-latest-backup.sh`; restore the matching world folder only while the new server is stopped.

## What you need before starting

| Item | Why it is needed |
| --- | --- |
| An Ubuntu WSL 2 distribution with `sudo` access | Local management machine |
| A GitHub account and GitHub CLI login | Clone, push, and validate the repository |
| A DigitalOcean account with billing enabled | Creates the Droplet, firewall, and SSH key |
| A DigitalOcean personal access token with write access | Used by Terraform; never commit or paste it into chat |
| A Tailscale account and a connected WSL device | Private SSH and the optional dashboard |
| A unique Valheim password, stored in a password manager | Required to start the game server |
| A backup destination outside the Droplet | Required before treating the world as recoverable |

The default Droplet is `s-2vcpu-4gb` in `nyc3`, listed at $24/month before taxes when this guide was written. The optional `s-4vcpu-8gb` size costs $48/month before taxes. DigitalOcean charges while a Droplet exists, including while it is powered off.

## 1. Prepare WSL

Update the base tools:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git gnupg openssh-client unzip
```

Create an SSH key if this WSL installation does not already have one. Keep the private key only in WSL and back it up through your normal secure-device process.

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519 -C "valheim-wsl"
```

Install and connect Tailscale in WSL. Use the same Tailscale account that will administer the Droplet.

```bash
curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
sudo sh /tmp/tailscale-install.sh
sudo tailscale up --hostname=valheim-wsl
tailscale status
```

Open the authorization link printed by the final command. The machine must appear in `tailscale status` before continuing.

Install and authenticate GitHub CLI if it is not already available. Authenticate with `repo` and `workflow` scopes if you will push this repository and its validation workflow. GitHub’s official installation and authentication instructions are the source of truth for the current package and login flow.

## 2. Clone the repository and install Terraform

```bash
cd ~/dev
git clone https://github.com/safranklin/valheim-server.git
cd valheim-server
bash scripts/install-terraform.sh
```

The installer downloads Terraform 1.14.0 into the ignored `.tools/` directory and verifies its SHA-256 checksum. Use it directly in this guide:

```bash
.tools/terraform version
```

## 3. Store the DigitalOcean token locally

Create a DigitalOcean personal access token that can manage Droplets, SSH keys, firewalls, and tags. Keep its master copy in Bitwarden. Store a working copy only in WSL:

```bash
bash -c '
  mkdir -p ~/.config/valheim
  chmod 700 ~/.config/valheim
  umask 077
  read -r -s -p "Paste DigitalOcean API token: " token
  printf "\n"
  [ -n "$token" ] || exit 1
  printf "%s" "$token" > ~/.config/valheim/digitalocean-token
  chmod 600 ~/.config/valheim/digitalocean-token
  unset token
'
```

For each terminal session that runs Terraform, load the token without printing it:

```bash
export DIGITALOCEAN_TOKEN="$(< ~/.config/valheim/digitalocean-token)"
```

The token, `.env`, Terraform state, plans, downloaded archives, and `.tools/` are excluded from Git. Confirm before committing:

```bash
git status --ignored --short
```

## 4. Choose the server size and create the infrastructure

The defaults already select 2 vCPU / 4 GB. Copy the example only if you want an explicit local choice or want to select the 8 GB option:

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
chmod 600 infra/terraform.tfvars
```

Run a reviewable plan, then apply exactly that plan:

```bash
.tools/terraform -chdir=infra init
.tools/terraform -chdir=infra plan -input=false -out=server.tfplan
.tools/terraform -chdir=infra apply -input=false server.tfplan
```

This creates:

- Ubuntu 24.04 Droplet in `nyc3`
- A DigitalOcean SSH-key record for `~/.ssh/id_ed25519.pub`
- DigitalOcean monitoring
- A firewall allowing public UDP `2456-2458` for Valheim
- TCP `8080` only from Tailscale’s CGNAT range `100.64.0.0/10` for the health dashboard
- No public SSH rule

Terraform state remains local in `infra/terraform.tfstate`. Back it up privately. Do not commit it. If the same public key was already added to DigitalOcean outside Terraform, import that key before applying or remove the duplicate key record from the DigitalOcean console:

```bash
.tools/terraform -chdir=infra import digitalocean_ssh_key.valheim DIGITALOCEAN_KEY_ID
```

## 5. Enroll the Droplet in Tailscale

The Droplet installs Docker, Tailscale, and security updates through cloud-init, but it cannot join your private Tailscale network until you authorize it. Public SSH is intentionally closed, so do this through DigitalOcean’s Recovery Console:

1. In the DigitalOcean console, open the Droplet’s **Settings** tab.
2. Use **Reset root password** and retrieve the temporary password from email.
3. Open **Recovery console**. Do not use the SSH-based Web Console; the firewall blocks public SSH.
4. Log in as `root`, change the temporary password, and save it in Bitwarden.
5. Run:

   ```bash
   cloud-init status --wait
   tailscale up --hostname=fartheim
   tailscale ip -4
   ```

6. Open the Tailscale authorization link and approve the device. In WSL, set its returned Tailscale IP for the current terminal:

   ```bash
   export VALHEIM_HOST=100.x.y.z
   ssh "root@$VALHEIM_HOST" 'hostname && docker compose version'
   ```

Tailscale device-expiry and access policies apply. Ensure the WSL device is permitted to reach the server on TCP 22. Players do not need Tailscale.

## 6. Configure and start Valheim

Create the ignored game configuration. Use a password at least 12 characters long. Quote it if it contains `$`, `#`, spaces, or punctuation.

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` to set `SERVER_NAME`, `WORLD_NAME`, `SERVER_PASS`, and `SERVER_PUBLIC`. Then deploy:

```bash
bash scripts/deploy.sh
```

The first startup downloads the Valheim dedicated server from Steam and can take several minutes. Confirm it is ready:

```bash
ssh "root@$VALHEIM_HOST" 'cd /opt/valheim && docker compose ps'
ssh "root@$VALHEIM_HOST" 'cd /opt/valheim && docker compose logs --tail=100 -f'
```

The tracked configuration starts a crossplay public server with 3× resources (`-modifier resources most`). Steam, Xbox, and Game Pass players can join through the public Droplet IPv4 address and port `2456`. Deploy crossplay changes while the server is empty, then test each player platform.

## 7. Dashboard, backups, and routine operations

The tracked configuration enables the container’s read-only status page. From a Tailscale-connected device, open:

```text
http://YOUR_TAILSCALE_SERVER_IP:8080/
```

The page is not exposed through the public Internet. Applying a Compose configuration change recreates the Valheim container and briefly disconnects players, so deploy dashboard or configuration changes only while the game is empty.

The container creates an archive at five minutes past every hour and retains seven days / up to 168 archives on the Droplet. These are not off-server backups. Configure automatic private Spaces uploads by following [BACKUPS.md](BACKUPS.md), or download and verify the newest archive:

```bash
bash scripts/fetch-latest-backup.sh
```

It stores the archive in `~/dev/ValheimBackups` by default, verifies the remote SHA-256 hash, and refuses to replace a same-named local file with different contents. Copy these archives to a second system or object storage. A Google Drive upload is not configured yet.

Useful commands:

```bash
# Live logs
ssh "root@$VALHEIM_HOST" 'cd /opt/valheim && docker compose logs --tail=100 -f'

# Current container state
ssh "root@$VALHEIM_HOST" 'cd /opt/valheim && docker compose ps'

# Download all retained on-server archives
bash scripts/backup.sh

# Validate infrastructure without touching DigitalOcean
.tools/terraform -chdir=infra validate
```

## Recovery and retirement

Before any risky server change, fetch and verify an archive. Restore only with the Valheim container stopped, and preserve the current world files before replacing anything. The world directory format in Valheim 1.0 contains several matching files; restore the full world directory, not just one file.

Terraform has `prevent_destroy` on the Droplet to protect the world disk. To retire it, first verify off-server backups, deliberately remove that lifecycle protection, review the destroy plan, and then apply it. A normal power-off does not stop DigitalOcean billing.

## Deployment checklist for a model or operator

1. Confirm `tailscale status` shows the WSL device.
2. Confirm `DIGITALOCEAN_TOKEN` is set but never print it.
3. Run a Terraform plan and verify exactly one Droplet, one firewall, and one SSH key will be created.
4. Apply the saved plan only after cost and region are correct.
5. Use the Recovery Console to enroll Tailscale and obtain the server’s Tailscale IP.
6. Create `.env` locally, keep it mode `600`, and do not add it to Git.
7. Deploy only after `cloud-init status --wait` succeeds.
8. Confirm Valheim reports a ready server and test one player connection.
9. Fetch and verify an off-server archive before treating the deployment as complete.
