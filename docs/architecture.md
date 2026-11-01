# Architecture

DEN is one current Fedora Server host. Bash owns provisioning and lifecycle commands; Docker Compose owns container ordering/readiness. Traefik's file provider reads generated routes, so it needs no Docker socket and there are no per-application proxy instructions. Applications keep their own household accounts; there is no extra identity-provider stack.

| Layer | Choice |
| --- | --- |
| Public transport | IPv4 TCP 80/443; HTTP-01 certificates and HTTPS |
| Private access | Traefik LAN/VPN IP allowlist; host WireGuard UDP 41873 |
| Proxy | Traefik 3.7.17, fixed `172.30.44.2` inside Compose |
| Containers | Docker CE and Compose v2 from Docker's Fedora repository |
| Applications | Jellyfin 12.4, Immich 3.3.5, Nextcloud 33.0.10, Forgejo 17.0.1 |
| Photo database | Immich's release-matched PostgreSQL 14 / VectorChord image |
| File database | PostgreSQL 17, frozen to a registry manifest digest |
| Queues/cache | Separate Valkey services for Immich and Nextcloud |
| Git database | SQLite, appropriate for a small household |
| Recovery | Encrypted, cold Restic snapshots on a separate mounted disk |
| Monitoring | systemd timers, journal, terminal status; no dashboard stack |
| Maintenance | Monthly automatic DEN/Fluxer/Fedora updates, migrations and required reboots |
| Optional credentials | Root-only KeePass-compatible KDBX file; no password-manager service |
| Optional chat | Upstream Fluxer `rexctl` stack behind Traefik, private LAN/VPN route |
| Optional downloads | qBittorrent 5.3.0 in the `torrents` Compose profile, private LAN/VPN route |

All core container images are pinned to manifest digests resolved on 2026-10-31. Immich server and machine learning have the same release. The eleven core containers share one fixed bridge subnet; this is a simplicity tradeoff, not strong isolation between applications. Databases and application listeners have no published host ports. Only Traefik publishes core TCP ports, bound to `LAN_IP`. Optional Fluxer runs in its own Rexctl-managed Docker project and is routed from Traefik through the core bridge gateway; its full archives are saved inside `/srv/den` before every Restic snapshot. Host WireGuard and VPN DNS are outside Compose. Fedora firewalld remains enabled; `wg0` is assigned to its trusted zone for the explicitly allowed VPN-to-LAN path. SELinux remains enabled, with shared labels on DEN's core container bind mounts.

## Storage Contract

| Host location | Contents |
| --- | --- |
| `/opt/den` | Installed release, generated `.env`, routes, private device profiles |
| `/opt/den/fluxer` | Optional Rexctl-managed instance settings and verified Rexctl binary |
| `/srv/den/media/{movies,tv,music}` | Household media, read-only in Jellyfin |
| `/srv/den/jellyfin` | Media-server config and metadata |
| `/srv/den/immich/{library,database}` | Photos and matched PostgreSQL files |
| `/srv/den/nextcloud/{html,database}` | Files, Nextcloud config/apps, PostgreSQL files |
| `/srv/den/forgejo` | Repositories, config, SQLite, attachments |
| `/srv/den/qbittorrent` | Optional torrent preferences, password hash, resume state |
| `/srv/den/downloads/{complete,incomplete}` | Optional finished and partial downloads, included in backups |
| `/srv/den/traefik` | Private ACME state and certificates |
| `/srv/den/system/deployment` | Deployment copy saved before every backup |
| `/srv/den/fluxer/backups` | Optional full Fluxer archives included in Restic snapshots |
| `/srv/den/cache` | Regenerable Jellyfin/Immich caches; not backed up |
| `BACKUP_MOUNT/den-restic` | Encrypted backup repository |

Bind mounts, not anonymous application volumes, make the backup boundary visible. Installation creates directories and establishes initial ownership; application images manage their own database/file ownership. DEN does not recursively change ownership of existing application data during recovery.

New installs using the example bind `MEDIA_MOUNT/den/media` and
`MEDIA_MOUNT/den/downloads` from the larger secondary HDD to the unchanged
`/srv/den` paths above. Databases, app settings and caches remain on the primary
SSD. systemd mount units and a Docker drop-in order boot against persistent HDD
mounts; DEN checks their identity before startup and backup. Restic follows these
bind mounts, so snapshots still have a single `/srv/den` root. Empty or absent
`MEDIA_MOUNT` preserves the legacy single-disk layout. Fluxer live object-store
volumes remain upstream-managed on SSD; no local HDD-media override is applied.

## Repository Map

`install.sh` prepares a fresh host; `recover.sh` restores an empty host; `update.sh` submits a reviewed checkout to the installed CLI. `bin/den` dispatches root-only commands with a shared lock. `lib/core.sh` parses config without evaluating shell code. `lib/deploy.sh` owns Compose, routes, storage, VPN, and host setup. `lib/backup.sh` owns cold snapshots and staged restore. `lib/keepass.sh` manages the optional encrypted credential export. `lib/fluxer.sh` bridges the optional Rexctl-managed stack into DEN's proxy, backup, recovery, and update paths. `lib/maintenance.sh` owns health checks and release updates. `templates` holds the fixed stack and systemd units. `tests` has non-root contract, failure-path, and real Restic checks.

Simplicity over flexibility, one server first, mature tools, fixed defaults, and practical outcomes are intentional constraints. Recovery from backup is the availability strategy. Clustering, failover, alternative app choices, enterprise scaling, and arbitrary extensions are out of scope.