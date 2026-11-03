# Technical Reference

For administrators and contributors. For normal use, start with
[setup checklist](installation.md).

## Components

One Fedora Server host runs Docker Compose for Jellyfin, Immich, Nextcloud,
Forgejo and optional qBittorrent. Traefik handles HTTPS without a Docker socket.
Fluxer uses its own upstream `rexctl` stack. WireGuard and VPN DNS run on the host.
Cockpit runs as a Fedora socket-activated host service by default. Traefik exposes
`server.DOMAIN` through the private middleware with a verified TLS backend.
Core images are pinned by digest in `templates/compose.yml`.
An internal nginx container serves the LAN/VPN-only `home.DOMAIN` landing page.
Installation, release updates and recovery generate `/opt/den/home/index.html`
from the HTML template, configured domain/LAN IP and enabled services. The page
links to GitHub instead of embedding installation instructions, and includes a
local copy of the mascot from `docs/images/mascot.png`.
Only this generated directory is mounted read-only into nginx;
deployment secrets are not served. No extra host port is published.

| Network item | Value |
| --- | --- |
| WireGuard | UDP 41873, `10.44.0.0/24` |
| Docker bridge | `172.30.44.0/24`, gateway `.1`, allocation `.128/25` |
| Traefik | Fixed `172.30.44.2`; host TCP 80/443 bound to `LAN_IP` |
| Fluxer backend | `172.30.44.1:29461` |
| Cockpit backend | `172.30.44.1:9090`, TLS; edge `.2` only |
| Fluxer voice | TCP 7881, UDP 7882, public when enabled |
| qBittorrent Web UI | Internal 18427; no published UI/peer ports |

Generated `routes.json` is mounted as `routes.yml` for Traefik's file provider.
Nextcloud trusts only Traefik's address. VPN DNS listens on `10.44.0.1`.

## Firewall

`den-firewall.service` loads `/etc/den/network.nft` before Docker.
The `inet den_guard` prerouting chain runs at -110, before Docker DNAT at -100.
It permits LAN, scoped VPN, return traffic and essential network control.
Outside access is limited to WireGuard, plus TCP 80 for HTTP-01 certificates.
Enabled Fluxer also admits IPv4 TCP 443/7881 and UDP 7882 addressed to `LAN_IP`.
Only chat omits Traefik's private middleware; the other apps remain allowlisted.
IPv6 application access is blocked.

Firewalld's `den-vpn` zone accepts traffic admitted by the guard. The Cockpit
backend restriction precedes LAN/VPN and bridge allowances. Other internal Docker
traffic remains trusted; this is not general inter-container isolation.

```bash
sudo nft list table inet den_guard
sudo nft --check --file /etc/den/network.nft
sudo systemctl reload den-firewall
```

Reload affects only DEN's table. Stopping the unit does not remove its rules.

## Paths and Storage

| Path | Contents |
| --- | --- |
| `/opt/den` | Installed code, `.env`, private keys and profiles |
| `/srv/den/SERVICE` | App settings/data; Jellyfin metadata on SSD |
| `/srv/den/media` | Jellyfin media, mounted read-only as `/media` |
| `/srv/den/downloads` | Complete/incomplete downloads |
| `/srv/den/fluxer/backups` | Rexctl archives |
| `/srv/den/system/deployment` | Installed release saved with each snapshot |
| `/srv/den/cache` | Regenerable caches, excluded from backup |
| `BACKUP_MOUNT/den-restic` | Encrypted snapshots |

`MEDIA_MOUNT/den/{media,downloads}` bind to the matching `/srv/den` paths.
systemd mount units and Docker dependencies prevent startup on missing storage.
Restic follows these mounts. Empty `MEDIA_MOUNT` keeps data on SSD.
Shared media/backup storage requires `ALLOW_SHARED_MEDIA_BACKUP=yes`.

`templates/compose.torrents.yml` exposes completed downloads read-only to
Jellyfin only when qBittorrent is enabled. Fluxer live volumes stay in Docker's
data root, not `MEDIA_MOUNT`.

With `QBITTORRENT_VPN_ENABLED=yes`, `templates/compose.torrent-vpn.yml` adds a
pinned Gluetun sidecar. qBittorrent shares its network namespace; Traefik routes
the private downloads Web UI to the sidecar's port 18427. No host ports are
published. Only the sidecar receives NET_ADMIN and `/dev/net/tun`; its firewall
blocks non-tunnel egress, with no LAN outbound bypass. IPv6 is disabled and
qBittorrent's resolver points to the sidecar's loopback DNS. Profiles are parsed
as data under `private/torrent-vpn`, never executed with wg-quick. Missing
profiles leave torrent services stopped. See [upload and modes](qbittorrent.md#optional-torrent-vpn).

## Release Updates

`bin/den` serializes operations with a lock. Config is parsed as data, not shell.
Releases pull images, back up, preserve secrets and wait for healthy apps.
Publish a new `VERSION`; numeric version tags must match it.
Nextcloud major upgrades must be sequential.

Database major changes require tested `migrations/immich-db-OLD-NEW.sh` or
`migrations/nextcloud-db-OLD-NEW.sh`, with `DEPLOY_DIR` and `DATA_DIR` exported.
Missing migrations are rejected. An interrupted update leaves
`private/update-in-progress` and blocks retry until repaired.
Application snapshots are not an OS rollback.

Fedora maintenance selects the next stable release, not skipped majors or
Rawhide. Private repository credentials must be configured separately on recovery.
Fluxer updates/recovery unset the previous `voice.public_ip` LAN override so
Rexctl/LiveKit discovers the public address; enabled chat becomes public on update.

## Repository

Entry points: `install.sh`, `update.sh`, `recover.sh`, `bin/den`.
Implementation: `lib/`; generated config: `templates/`; checks: `tests/`.
See [testing](testing.md) for development and release validation.
