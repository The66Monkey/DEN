# Optional qBittorrent

DEN can run qBittorrent 5.3.0 using a digest-pinned LinuxServer image. It is
disabled by default. Download or seed only material you have permission to share.

## Production Setup

Before installing, set `QBITTORRENT_ENABLED=yes` in your install config. Add
public DNS and LAN overrides for `downloads.DOMAIN`, like the other apps.
DEN routes `https://downloads.DOMAIN` through Traefik with the same LAN/WireGuard
allowlist and valid HTTPS certificates. No direct Web UI or peer port is
published by Compose, and no extra firewall ports are opened.

Sign in as `admin`. Retrieve the initial temporary password locally:

```bash
sudo den logs qbittorrent
```

Immediately set a permanent, unique password in the Web UI settings. Until
then, the temporary password changes on every restart. Do not share unredacted
logs. If you use KeePass, add this application-managed password to your vault
yourself; DEN does not generate or export it automatically.

Authentication, host-header checks, and CSRF protection remain enabled. Do not
disable them to troubleshoot a proxy. UPnP/NAT-PMP is disabled in the initial
configuration. Keep it disabled, and do not forward the Web UI or torrent ports
at the router. Without incoming peer ports, outbound connections can still
transfer data, but availability and seeding may be reduced.

**There is no outbound VPN or kill switch.** Trackers and peers can see your
normal public IP. DEN's WireGuard lets your devices reach home; it does not
hide server-originated traffic. A commercial-VPN deployment is not provided.

## Storage and Lifecycle

| Host path | Container path | Purpose |
| --- | --- | --- |
| `/srv/den/qbittorrent` | `/config` | Preferences, password hash, torrent/resume state |
| `/srv/den/downloads/complete` | `/downloads/complete` | Finished downloads |
| `/srv/den/downloads/incomplete` | `/downloads/incomplete` | Work in progress |

With the default example's `MEDIA_MOUNT=/mnt/den-storage`, both download
folders live on the larger HDD at `MEDIA_MOUNT/den/downloads`, persistently
bind-mounted to the paths above. Preferences and resume state stay on SSD.
Jellyfin libraries likewise live at `MEDIA_MOUNT/den/media`. These paths are
scripted at install time; no Web UI storage changes are needed.

When qBittorrent is enabled, DEN also mounts the completed-download directory
read-only into Jellyfin at `/downloads/complete`. In Jellyfin's dashboard,
add a Movies library using that path, then scan it. If you download different
media types, use qBittorrent category save folders such as
`/downloads/complete/movies` and `/downloads/complete/tv` and add separate
Jellyfin libraries for those folders. Only completed files are exposed;
incomplete downloads are not.

Jellyfin can download metadata and artwork to its writable `/config` and
`/cache` directories without modifying media files. Leave options to save
NFO files or artwork alongside media disabled. Deletion or editing of the
media itself is intentionally unavailable. Files stay in place for qBittorrent
to seed; do not move or rename them outside qBittorrent while seeding.
qBittorrent does not receive write access to existing `/media` libraries.

The optional Compose profile is selected by DEN's command wrapper, so `den
start`, `stop`, `status`, `logs qbittorrent`, `check`, `backup`, and `update`
include it when enabled. Use DEN commands, not a bare `docker compose` command
which may omit the optional profile. Existing environments without the new
setting retain the disabled behavior.

Backups include configuration, completed downloads, and partial downloads.
qBittorrent stops with the other containers for a consistent snapshot, and
restarts only if it was previously running. Downloads can significantly grow
backup size and downtime: allow enough space on both the live and backup disks.
Recovery preserves saved preferences and passwords rather than initializing
them again.

### Sharing the Media and Backup HDD

A simple home setup can use an SSD for apps/settings and one HDD for media,
downloads and snapshots:

```text
MEDIA_MOUNT=/mnt/den-backup
BACKUP_MOUNT=/mnt/den-backup
ALLOW_SHARED_MEDIA_BACKUP=yes
```

The shared-storage option defaults to `no` for compatibility with separate-disk
setups. Backups still cannot use the OS filesystem.

Live media/downloads use `MOUNT/den/media` and `MOUNT/den/downloads`;
Restic stays separate at `MOUNT/den-restic`. The backup reads only `/srv/den`,
including its media/download bind mounts, not the repository itself. A shared
HDD failure loses both live media and its snapshots; a separate disk provides
protection against that. Allow room for downloads and snapshot history.

Changing the environment on an existing server does **not** migrate files.
Stop services, copy and verify existing media/downloads preserving ownership
and permissions, then install persistent bind mounts and Docker dependencies
before restarting. Never mount over nonempty directories to hide existing data
or rerun the installer on an existing deployment.

## Local Rootless Podman Test

The optional Quadlet is separate from the production installer. It uses the
same pinned image at `http://192.168.50.109:37952`, with persistent storage under
`/mnt/Storage/den-local`. Adjust UID/GID, LAN IP, and mount path before using the
example on another machine.

From the checkout, after preparing the local network in [testing](testing.md):

```bash
(
set -eu
mountpoint -q /mnt/Storage
mkdir -p /mnt/Storage/den-local/qbittorrent/config
mkdir -p /mnt/Storage/den-local/downloads/{complete,incomplete}
source lib/core.sh
source lib/deploy.sh
prepare_qbittorrent_config /mnt/Storage/den-local/qbittorrent/config 192.168.50.109
)
cp templates/podman/den-qbittorrent-local.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start den-qbittorrent-local.service
```

Use `podman logs den-qbittorrent-local` privately for the temporary `admin`
password, then change it. Completed files are in
`/mnt/Storage/den-local/downloads/complete`. Like the other local services, it is
HTTP-only, has no automatic backup, and has no guaranteed boot startup. A LAN-IP
change requires updating both the Quadlet and qBittorrent's allowed server name.

```bash
podman healthcheck run den-qbittorrent-local
systemctl --user stop den-qbittorrent-local.service
```

Stopping preserves downloads and settings. The local test does not deploy
production DNS, TLS, WireGuard, or backup timers.
