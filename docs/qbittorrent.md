# Downloads and Jellyfin

## Enable qBittorrent

Before installation, set `QBITTORRENT_ENABLED=yes` and add the `downloads`
DNS name as described in [networking](networking.md).

Open `https://downloads.your-domain`. Sign in as `admin`; get the temporary
password over SSH:

```bash
sudo den logs qbittorrent
```

Set a permanent password in the Web UI immediately. Until then, restarting
changes the temporary password. Keep UPnP/NAT-PMP disabled and do not forward
torrent or Web UI ports. Only download material you have permission to share.

**WireGuard does not hide torrent traffic.** Trackers and peers see your normal
public IP. DEN does not provide an outbound VPN or kill switch.

## Watch Completed Downloads

In Jellyfin: **Dashboard → Libraries → Add Media Library**.
Choose Movies and add `/downloads/complete`, then scan.

For mixed media, use qBittorrent category folders such as
`/downloads/complete/movies` and `/downloads/complete/tv`; add separate Jellyfin
libraries for each.

Jellyfin reads completed files without modifying them, so seeding can continue.
Posters and metadata stay in its configuration. Leave options to save artwork
or NFO files beside movies disabled. Do not move seeding files outside qBittorrent.

| On the server | Inside qBittorrent |
| --- | --- |
| `/srv/den/downloads/complete` | `/downloads/complete` |
| `/srv/den/downloads/incomplete` | `/downloads/incomplete` |
| `/srv/den/qbittorrent` | `/config` |

Use `sudo den start`, `stop`, `status` and `logs qbittorrent` to manage it.
Settings and both download folders are included in nightly snapshots.

### Sharing the Media and Backup HDD

For one HDD holding media, downloads and snapshots:

```text
MEDIA_MOUNT=/mnt/den-backup
BACKUP_MOUNT=/mnt/den-backup
ALLOW_SHARED_MEDIA_BACKUP=yes
```

The HDD holds `den/media`, `den/downloads` and `den-restic`.
Apps/settings remain on SSD. Disk failure loses both media and its snapshots;
a separate backup disk protects against that. Allow space for snapshot history.

These are installation settings, not migration commands. Changing them on an
existing server does not move files; arrange an offline migration instead.
