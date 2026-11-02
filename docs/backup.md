# Back Up and Recover

## What DEN Saves

Restic saves encrypted snapshots at `BACKUP_MOUNT/den-restic`. The HDD can be shared with media/downloads using the [shared-storage setting](qbittorrent.md#sharing-the-media-and-backup-hdd). Snapshots include `/srv/den` and a saved copy of `/opt/den`: application data, settings, passwords, VPN keys and certificates. Optional Fluxer archives and qBittorrent downloads are included too. Regenerable caches are excluded.

DEN stops all stack containers before copying application data into the repository and restarts only the previously running services afterward, including when the backup fails. This is a cold file-level backup, not a live database dump. There is no snapshot if Docker cannot confirm the stack is stopped. VPN and VPN DNS stay up. Downtime depends on changed data size and disk speed; a large first backup can take hours. Recovery uses the saved database image versions rather than trying to import old files into newer databases.

When qBittorrent is enabled, its settings, password hash, torrent/resume state,
and all completed and partial downloads are included. It follows the same
stop/restart policy. Budget backup space and downtime for large downloads.
Recovered settings are preserved; a saved permanent password remains valid.

The timer runs nightly around 03:00 with up to 15 minutes of random delay. Missed jobs run after boot. `den check` flags a backup older than 36 hours. A missing USB disk fails closed instead of writing to an empty mountpoint on the server disk.

```bash
sudo den backup
sudo den snapshots
journalctl -u den-backup.service --since yesterday
```

Nightly snapshots are automatic; you do not need to make extra manual backups
during everyday use. No snapshots are deleted automatically in 0.1.0.
When space runs low, remove older snapshots with:

```bash
sudo den prune
```

`prune` keeps 7 daily, 4 weekly, and 6 monthly snapshot buckets, sharing unchanged
data between snapshots. It permanently removes older history.
If you suspect a backup problem, `sudo den verify-backup` checks the repository;
it can take a while.

## Save the Recovery Kit

```bash
sudo den recovery-kit /media/recovery-usb
```

Keep this private USB copy somewhere accessible if the server fails. It contains
the encryption password, DNS token, VPN keys and deployment scripts, not household
data. Restic cannot reset a lost encryption password. Refresh it after changing
VPN profiles or the installed release. Additional off-site copies are optional;
for most households, prioritize photos and files you cannot replace.

## Practice a Restore

Choose an explicit ID from `sudo den snapshots`, not `latest`:

```bash
sudo den restore SNAPSHOT_ID /srv/den-restore-drill
```

The target must not already exist. Restic verifies the restore and places data at `/srv/den-restore-drill/srv/den`. Open a restored test file, compare it with the original, and check that `system/deployment/.env` exists with mode 600. Live services are not changed. Never start a second DEN stack against the same data. Remove the drill directory only after verifying it and checking the path carefully.

## Recover a Failed Server

1. Install a fresh Fedora Server host with the same supported CPU class and LAN IPv4. Reserve that address and point the router forwards at it. Mount the backup disk at the original path. If the saved environment has `MEDIA_MOUNT`, mount the replacement HDD there too, with empty `den/media` and `den/downloads` folders and a persistent UUID entry in `/etc/fstab`. Do **not** run the normal installer first.
2. Attach your saved recovery kit. Run its saved recovery code so the restore uses the backed-up release:

```bash
cd /media/recovery-usb/den-recovery-kit
sudo bash recover.sh /media/recovery-usb/den-recovery-kit/.env SNAPSHOT_ID
```

3. DEN installs host dependencies, verifies the restore in a new staging directory, moves the restored data into an empty `/srv/den`, installs the saved deployment and VPN keys, pulls the saved pinned core images, and starts the core services. When Fluxer is enabled, recovery restores its newest full archive with the saved Rexctl binary.
4. Verify HTTPS, users, photo download, media playback, file download, Git clone, Fluxer chat/attachments, and VPN from another network. Run `sudo den backup` and `sudo den check`.

For secondary storage, recovery stages the verified snapshot on the HDD,
moves media/downloads into its live folders without making a second bulk-data
copy, and promotes the remaining settings/databases onto SSD. It recreates
the persistent bind mounts before starting services. A restore drill still
uses the staging path you provide; choose the HDD if the snapshot exceeds
available SSD space.

Root paths and LAN identity must be unchanged in 0.1.0. Restoring to different subnets/domains requires a migration and is not part of this simple recovery path. Old snapshots may contain subsequently revoked VPN peers; revoke those devices again before enabling remote access. Recovery requires internet access to obtain Fedora packages, Docker CE, pinned container images, and (when Fluxer is enabled) its upstream releases.

## Recover After a Bad Update

Do not just switch to an older image: databases and Nextcloud data may have migrated. Keep the failed deployment intact. Stop the timers and services, then move both live roots to unused holding names before running recovery from the kit:

**For secondary-storage hosts, do not use the single-disk commands below.**
After stopping DEN and Fluxer, stop Docker, disable the two generated mount
units (`srv-den-media.mount` and `srv-den-downloads.mount`), and preserve their
unit files and `/etc/systemd/system/docker.service.d/den-storage.conf` under
unused holding names. Move the HDD's `den/media` and `den/downloads` folders
to unused holding names on that disk after unmounting them, then preserve the
SSD roots and host configuration as below. Reload systemd before recovery.
Never move `/srv/den` with active bind mounts, or leave old HDD data in the
recovery destination. Have enough space for both retained data and the restored
snapshot; do not delete the retained data to make room without another copy.

```bash
sudo systemctl stop den-update.timer den-backup.timer den-check.timer den.service den-dns.service wg-quick@wg0.service
sudo den stop
sudo mv /srv/den /srv/den-before-recovery
sudo mv /opt/den /opt/den-before-recovery
sudo mv /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.before-den-recovery
sudo mv /etc/systemd/system/den.service /etc/systemd/system/den.service.before-den-recovery
sudo systemctl daemon-reload
```

Those holding paths must not already exist. Then use the failed-server procedure with the **pre-update** snapshot. Retain holding directories until the recovered applications have passed verification. This manual promotion is intentionally explicit; `den restore` never silently overwrites live data. Changes since the selected snapshot will not be in the recovered system.

## What Has Been Tested

The automated suite exercises real Restic encryption, saved-secret permissions, cache exclusions, verified file restore, bad passwords, stopped-stack ordering, failed backup/restart reporting, and unsafe target rejection. It uses mock Docker for lifecycle checks. Recovery of actual application databases and full bare-metal provisioning remain the manual acceptance gates in [testing](testing.md).