# Architecture

DEN is one Debian 13 Stable server. Bash owns provisioning and lifecycle commands; Docker Compose owns container ordering/readiness. Traefik's file provider reads generated routes, so it needs no Docker socket and there are no per-application proxy instructions. Applications keep their own household accounts; there is no extra identity-provider stack.

| Layer | Choice |
| --- | --- |
| Public transport | IPv4 TCP 80/443; HTTP-01 certificates and HTTPS |
| Private access | Traefik LAN/VPN IP allowlist; host WireGuard UDP 51820 |
| Proxy | Traefik 3.7.17, fixed `172.30.44.2` inside Compose |
| Containers | Debian's Docker Engine and Compose v2 packages |
| Applications | Jellyfin 12.4, Immich 3.3.5, Nextcloud 33.0.10, Forgejo 17.0.1 |
| Photo database | Immich's release-matched PostgreSQL 14 / VectorChord image |
| File database | PostgreSQL 17, frozen to a registry manifest digest |
| Queues/cache | Separate Valkey services for Immich and Nextcloud |
| Git database | SQLite, appropriate for a small household |
| Recovery | Encrypted, cold Restic snapshots on a separate mounted disk |
| Monitoring | systemd timers, journal, terminal status; no dashboard stack |

All container images are pinned to manifest digests resolved on 2026-10-31. Immich server and machine learning have the same release. The eleven containers share one fixed bridge subnet; this is a simplicity tradeoff, not strong isolation between applications. Databases and application listeners have no published host ports. Only Traefik publishes TCP ports, bound to `LAN_IP`. Host WireGuard and VPN DNS are outside Compose.

## Storage Contract

| Host location | Contents |
| --- | --- |
| `/opt/den` | Installed release, generated `.env`, routes, private device profiles |
| `/srv/den/media/{movies,tv,music}` | Household media, read-only in Jellyfin |
| `/srv/den/jellyfin` | Media-server config and metadata |
| `/srv/den/immich/{library,database}` | Photos and matched PostgreSQL files |
| `/srv/den/nextcloud/{html,database}` | Files, Nextcloud config/apps, PostgreSQL files |
| `/srv/den/forgejo` | Repositories, config, SQLite, attachments |
| `/srv/den/traefik` | Private ACME state and certificates |
| `/srv/den/system/deployment` | Deployment copy saved before every backup |
| `/srv/den/cache` | Regenerable Jellyfin/Immich caches; not backed up |
| `BACKUP_MOUNT/den-restic` | Encrypted backup repository |

Bind mounts, not anonymous application volumes, make the backup boundary visible. Installation creates directories and establishes initial ownership; application images manage their own database/file ownership. DEN does not recursively change ownership of existing application data during recovery.

## Repository Map

`install.sh` prepares a fresh host; `recover.sh` restores an empty host; `update.sh` submits a reviewed checkout to the installed CLI. `bin/den` dispatches root-only commands with a shared lock. `lib/core.sh` parses config without evaluating shell code. `lib/deploy.sh` owns Compose, routes, storage, VPN, and host setup. `lib/backup.sh` owns cold snapshots and staged restore. `lib/maintenance.sh` owns health checks and release updates. `templates` holds the fixed stack and systemd units. `tests` has non-root contract, failure-path, and real Restic checks.

Simplicity over flexibility, one server first, mature tools, fixed defaults, and practical outcomes are intentional constraints. Recovery from backup is the availability strategy. Clustering, failover, alternative app choices, enterprise scaling, and arbitrary extensions are out of scope.