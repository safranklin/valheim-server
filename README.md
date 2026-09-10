# Valheim on DigitalOcean

Private infrastructure repo for an unmodded, crossplay-enabled Valheim server: up to the standard 10 players, normally around 6, hosted in New York (`nyc3`). WSL is the management machine; it does not need to stay running for people to play.

## Cost and sizing

Default: Basic shared CPU, 4 vCPU / 8 GB (`s-4vcpu-8gb`), listed at $48/month before tax as checked September 9, 2026. The 2 vCPU / 4 GB alternative is $24/month and has less headroom. Neither size guarantees performance for large builds. Check actual region availability and pricing before applying. If $50 includes tax, the default may exceed it: use the $24 size initially or select another host.

No paid backups, volumes, snapshots, or object storage are provisioned. Included transfer still has limits; overages can add charges. Set billing alerts in DigitalOcean (alerts are not spending caps). Powering a Droplet off does not stop its charges. Deletion does, but deletes world data too.

## First deployment from WSL

1. Install Terraform (>=1.9, <2; CI uses 1.14.0), Git and OpenSSH. A local Terraform binary may be available under `.tools/terraform`; run `export PATH="$PWD/.tools:$PATH"` from this repo if using that copy.
2. Create a DigitalOcean API token with permissions to manage Droplets, SSH keys, firewalls and tags. Keep a master copy in Bitwarden and save a working copy privately (works from Bash or zsh):

   ```bash
   bash -c '
     mkdir -p ~/.config/valheim
     chmod 700 ~/.config/valheim
     umask 077
     read -r -s -p "DigitalOcean token: " token
     printf "\n"
     [ -n "$token" ] || exit 1
     printf "%s" "$token" > ~/.config/valheim/digitalocean-token
     chmod 600 ~/.config/valheim/digitalocean-token
     unset token
   '
   export DIGITALOCEAN_TOKEN="$(cat ~/.config/valheim/digitalocean-token)"
   ```

3. Copy the configuration and choose the size. The SSH public key defaults to `~/.ssh/id_ed25519.pub`. No public SSH port is opened; administration uses normal OpenSSH over Tailscale.

   ```bash
   cp infra/terraform.tfvars.example infra/terraform.tfvars
   chmod 600 infra/terraform.tfvars
   ```

   If the same SSH key is already registered with DigitalOcean, import its ID rather than trying to create it again: after initializing, run `terraform -chdir=infra import digitalocean_ssh_key.valheim KEY_ID`.

4. Review and apply the infrastructure:

   ```bash
   terraform -chdir=infra init
   terraform -chdir=infra plan -out=server.tfplan
   terraform -chdir=infra apply server.tfplan
   ```

5. Connect WSL and the Droplet to your Tailscale account. Install Tailscale in WSL using the official Linux instructions and run `sudo tailscale up`. On the Droplet, cloud-init installs Tailscale; use DigitalOcean's Recovery Console for initial access (the regular SSH-based Droplet Console cannot cross the closed SSH firewall). Run `cloud-init status --wait`, then `tailscale up --hostname=valheim` and open its login URL in your browser. The Recovery Console may require setting a root password through DigitalOcean first; SSH password authentication remains disabled. No Tailscale enrollment key is stored in Terraform state.

   Run `tailscale ip -4` on the Droplet and set `export VALHEIM_HOST=100.x.y.z` in WSL, replacing the example with that address. Tailnet access policy must allow your WSL device to reach the Droplet on TCP 22; your SSH key still authenticates the session. This uses OpenSSH over Tailscale, not the optional Tailscale SSH feature. Review device key expiry for the long-running server in the Tailscale admin console. Players do not need Tailscale.

6. Set server name, world and a unique password in `.env`. Use a password of at least 12 letters/numbers to avoid dotenv quoting pitfalls; do not include the password in the server name. Keep the world name stable after playing begins.

   ```bash
   cp .env.example .env
   chmod 600 .env
   # Edit .env before continuing.
   bash scripts/deploy.sh
   ```

   Verify the SSH host fingerprint through the DigitalOcean console on first connection. Bootstrap and the initial Steam server download take several minutes. Deployment completion is not proof the game is ready: inspect logs and test a join from Steam and Xbox/Game Pass.

## Joining and operations

Crossplay is enabled without client mods. Use the in-game Join Game menu and the server join code from the startup logs, or find the configured server name in the community list. Share the password privately. Join codes can change after restarts.

```bash
server_ip=$VALHEIM_HOST
ssh "root@$server_ip" 'cd /opt/valheim && docker compose logs --tail=100 -f'
ssh "root@$server_ip" 'cd /opt/valheim && docker compose ps'
```

The container checks for game updates and restarts when idle. To deploy a changed Compose configuration or refresh the container image, run `bash scripts/deploy.sh`; this can interrupt players, so do it while empty. The image uses the upstream `latest` tag; pin an image digest after a successful deployment if you want controlled image upgrades. Game updates inside the image remain automatic.

Your home public IP can change without updating Terraform. Tailscale can relay administration traffic when direct connections are unavailable. Cloud-init runs at creation, not on every deployment. Changing it can propose Droplet replacement; `prevent_destroy` blocks that to protect saves.

## Backups and recovery

Hourly archives are retained for seven days under `/opt/valheim/config/backups`. These are on the same disk as the world: they do not protect against losing the Droplet. Download them regularly, especially after play sessions:

```bash
bash scripts/backup.sh
```

This command copies existing archives; it does not force a new save. Wait for an hourly archive and confirm its timestamp before relying on it. Local downloads are retained until you remove them. Keep a second copy outside WSL. Automatic off-server backups are not configured.

To restore, stop the service with `docker compose stop` in `/opt/valheim`, preserve a copy of the existing config, and inspect the chosen archive before extracting it into a temporary directory. Restore the matching world files together into `/opt/valheim/config/worlds_local` (older saves use matching `.db` and `.fwl` files; preserve the whole world directory for directory-based saves). Keep `WORLD_NAME` consistent, then run `docker compose up -d`, check logs, and join to verify. Never overwrite an active world. Test recovery before trusting backups for important progress.

Terraform state is local under `infra/`, ignored by Git. Back it up privately too; losing it loses Terraform's resource mapping. Do not use GitHub Actions to apply this configuration until shared, locked remote state and deployment secrets have been configured. CI currently validates changes only and needs no cloud token.

Destroy protection is deliberate. To retire the server, first download and verify world backups, explicitly remove `prevent_destroy`, then review a destroy plan. Deleting infrastructure is irreversible for any saves left on its disk.

## References

- [DigitalOcean pricing](https://www.digitalocean.com/pricing/droplets)
- [Valheim dedicated server guide](https://valheim.com/support/a-guide-to-dedicated-servers/)
- [Valheim crossplay FAQ](https://valheim.com/support/crossplay-faq/)
- [Community container documentation](https://github.com/community-valheim-tools/valheim-server-docker)
- [DigitalOcean Terraform provider](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs)
- [Install Tailscale on Linux](https://tailscale.com/docs/install/linux)
- [OpenSSH over Tailscale](https://tailscale.com/docs/reference/ssh-over-tailscale)
