# Backup and Recovery

## Everyday Backups

DEN saves encrypted snapshots nightly around 03:00. Apps briefly stop during
the backup and restart afterwards; VPN stays up. No daily action is needed.
Snapshots include app data/settings, media, downloads, passwords and VPN profiles,
but not regenerable caches.

With the optional [independent infrastructure](infrastructure.md), DNS and the
shared edge remain running. Their private configuration and certificates are
included; AdGuard query logs, statistics and filter cache are not.

```bash
sudo den snapshots          # list saved snapshots
sudo den backup             # optional backup now
```

Snapshots are stored at `BACKUP_MOUNT/den-restic`. The disk must be mounted.
It can [share the media HDD](qbittorrent.md#sharing-the-media-and-backup-hdd);
if that disk fails, both copies of the media are lost.

When space runs low:

```bash
sudo den prune
```

This permanently removes older history, keeping 7 daily, 4 weekly and 6 monthly
snapshot buckets. Unchanged data is shared between snapshots.
Use `sudo den verify-backup` if you suspect repository damage.

## Save the Recovery Kit

With a USB mounted at your chosen path:

```bash
sudo den recovery-kit /media/recovery-usb
```

Keep the resulting `den-recovery-kit` folder private. It contains settings,
VPN keys and the password needed to decrypt snapshots, **not your files**.
Refresh it after changing VPN profiles or the installed release.

## Restore Files Without Replacing Live Data

Choose a snapshot ID from `sudo den snapshots` and a new, empty staging path:

```bash
sudo den restore SNAPSHOT_ID /srv/den-restore-check
```

The destination must not already exist. Verified files appear under
`/srv/den-restore-check/srv/den`. Live apps are unchanged.
Choose a staging location with enough space; never use live data or backup
repository folders. Remove the staging copy when finished.

## Recover a Failed Server

1. Install fresh Fedora Server with the original LAN IP. Mount the backup HDD
   at its original path. If `MEDIA_MOUNT` is set, also mount that disk with
   empty `den/media` and `den/downloads` folders.
2. Attach the recovery USB. **Do not run the normal installer.**
3. Use a snapshot ID from the backup:

   ```bash
   cd /media/recovery-usb/den-recovery-kit
   sudo bash recover.sh /media/recovery-usb/den-recovery-kit/.env SNAPSHOT_ID
   ```

4. Check `sudo den check`, open the apps and test VPN access.

Recovery needs internet access and restores the saved app versions, settings
and keys. A private update repository needs root Git access configured again.
Revoke any lost VPN devices again if the snapshot predates their removal.
Keep the original domain and paths; changing them is a separate migration.

## Recover After a Bad Update

Do not install older images over updated databases. Preserve the failed data
until recovery is verified.

1. Stop timers, DEN, Fluxer, VPN DNS and WireGuard.
2. For HDD media: stop Docker, unmount the media/download bind mounts, and
   preserve their unit files and Docker storage drop-in. Move the HDD's
   `den/media` and `den/downloads` to unused holding names.
3. Preserve `/srv/den`, `/opt/den`, `/etc/wireguard/wg0.conf` and the installed
   DEN service under unused holding names. Never move folders with active mounts.
4. Reload systemd, then follow failed-server recovery with a **pre-update**
   snapshot. Allow space for both retained and restored data.

This is an administrator repair, not a routine owner task. Ask for help if
unsure; do not delete data to make a retry work.

## Optional AI data

Enabled AI stores WebUI accounts/chats/uploads and DEN Ollama models under
`/srv/den/ai`. They are included in snapshots; both WebUI and a running native
Ollama are quiesced, then restarted to their previous state. Recovery preserves
the WebUI secret/admin database and provisions the pinned runtime again.
Workstation model weights are not backed up by DEN. See [AI operations](ai.md).
