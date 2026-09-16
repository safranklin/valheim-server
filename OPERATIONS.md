# Fartheim operations

- Server name: `Fartheim`
- World: `Fartguard`
- Crossplay: enabled (Steam, Xbox, and Game Pass)
- UDP ports: `2456-2458` published
- Health dashboard: configured for `http://100.88.224.24:8080/` over Tailscale only; it becomes live after the next planned configuration deploy
- Resource rate: 3× (`-modifier resources most`)
- DigitalOcean: `nyc3`, 2 vCPU / 4 GB, $24/month before tax
- Droplet ID: `599196276`
- Public game address: `45.55.130.209:2456`
- Tailscale administration: `100.88.224.24` (`fartheim`)

From this repository in WSL:

```bash
export VALHEIM_HOST=100.88.224.24
ssh "root@$VALHEIM_HOST" 'cd /opt/valheim && docker compose logs --tail=100 -f'
```

This is a crossplay server. Connect using the public game address above. The game password is in the ignored local `.env` and the restricted `/opt/valheim/.env` on the server.

PlayFab join codes are temporary identifiers for the currently running crossplay server. A code changes on restart, so players who depend on one need the newly issued code. The public address and the server-list entry remain the durable ways to find Fartheim.

Deploy configuration changes during an empty session:

```bash
bash scripts/deploy.sh
```

Download existing hourly backup archives:

```bash
bash scripts/backup.sh
```

Download only the newest archive to `~/dev/ValheimBackups`, with SHA-256 verification:

```bash
bash scripts/fetch-latest-backup.sh
```

Archives are retained on the Droplet for seven days. Downloaded copies persist in the ignored local `backups/` directory. Off-server downloads are manual; keep another copy outside WSL. See README.md for recovery steps.

Public SSH is blocked. Use Tailscale for routine access. If Tailscale access is lost, use DigitalOcean's **Recovery Console** (not the SSH-based **Web Console**). Its root password is managed separately from the game password.
