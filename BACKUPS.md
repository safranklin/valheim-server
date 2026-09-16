# Offsite backups

The Valheim container creates a compressed world archive at five minutes past every hour. `scripts/setup-spaces-backups.sh` copies those completed archives to a **private** DigitalOcean Spaces bucket at ten minutes past the hour, verifies the newest remote object with SHA-256, and keeps 90 days of archives. It does not restart the Valheim container.

Spaces is better than relying solely on Droplet snapshots for this server: it holds individual world archives that can be downloaded from the DigitalOcean control panel. A snapshot is still useful before a risky operating-system or game-server change, but it is a whole-Droplet recovery image, not the routine backup system.

## One-time setup

1. In the [DigitalOcean Spaces control panel](https://cloud.digitalocean.com/spaces), create a bucket in `nyc3` named `fartheim-backups-<a-unique-suffix>`. Leave it private. A Space has a $5/month minimum charge.
2. Open **Access Keys** and create a key named `fartheim-backup-writer`. Select **Limited access**, select only the new bucket, and grant **Read/Write/Delete**. Save the access-key ID and secret key; the secret is shown once.
3. From the repository checkout in WSL, run the following. It asks for the two Spaces credentials without echoing them, installs `rclone` on the Droplet, uploads the existing archives, verifies the latest upload, and enables the hourly timer.

```bash
cd ~/dev/valheim-server
VALHEIM_HOST=fartheim bash scripts/setup-spaces-backups.sh fartheim-backups-<a-unique-suffix>
```

The credentials never enter Git, Terraform state, or the container environment. The script writes `/root/.config/rclone/rclone.conf` on the Droplet with mode `0600`.

## Verify and recover

Check the timer and most recent transfer from WSL:

```bash
VALHEIM_HOST=fartheim bash scripts/check-spaces-backup.sh
```

In the DigitalOcean control panel, open **Spaces Object Storage**, select the private bucket, then browse `fartheim/worlds/`. Download a `worlds-YYYYMMDD-HHMMSS.zip` archive when you need a copy. Do not make the bucket or its objects public merely to share a backup; download the archive and share it deliberately.

To restore, follow the restore procedure in [README.md](README.md). Stop the container before replacing a world, preserve the current world first, and restore matching world files together. A successful upload verifies that the archive is readable from Spaces; test a real restore before depending on it for an important world.

## Retention and key rotation

The remote retention default is 90 days. Choose a different positive number while setting up the timer:

```bash
SPACES_RETENTION_DAYS=180 VALHEIM_HOST=fartheim bash scripts/setup-spaces-backups.sh fartheim-backups-<a-unique-suffix>
```

To rotate the credential, create a replacement limited key in the DigitalOcean control panel, rerun the setup command, verify an upload, then revoke the old key. Removing the key stops future uploads but does not delete existing objects.
