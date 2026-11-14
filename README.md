# DEN (Digital Environment for Networking)

An opinionated deployment framework that brings established open-source services
together into a complete home-server setup: photos, files, movies and private
remote access on one Fedora Server PC.
Use the apps from your phone or computer; no desktop is needed on the server.

<p align="center">
  <img src="docs/images/mascot.png" alt="DEN mascot" width="400">
</p>

## What You Get

- **Jellyfin** — watch movies, TV and music.
- **Immich** — upload and browse phone photos.
- **Nextcloud** — sync and share files.
- **Forgejo** — keep your Git projects at home.
- **WireGuard** — connect privately from your phone or computer.
- **Automatic backups and updates** — routine maintenance is built in.
- **Cockpit** — Fedora host administration at `https://server.YOUR-DOMAIN` on
  LAN/VPN, enabled by default with [opt-out](docs/operations.md#cockpit-administration).
- **Home page** — open `https://home.YOUR-DOMAIN` on LAN/VPN for service links,
  SSH instructions and this README.

**Optional:** qBittorrent with a separate torrent-only provider VPN, Fluxer for
chat and calls, and a KeePassXC-compatible password vault.
When Fluxer is enabled, the home page links to both its main chat interface and
administration at `https://chat.YOUR-DOMAIN/admin`.

Advanced enthusiast services live in the separate
[DEN+ add-on repository](https://git.scandinavianhacking.dedyn.io/The66Monkey/DEN-plus).
They are not part of the core DEN installation. Existing enhanced installations
must follow the add-on migration guide before updating; this repository split
does not migrate or stop a running server.

For a host sharing its public IP with a VM, use the optional
[independent DNS and shared edge topology](docs/infrastructure.md): infrastructure
runs on DEN, while the VM remains an application backend.

Everything runs on one Fedora Server PC. Photos, files, media, Git and downloads
stay on your home network/VPN. **Enabling Fluxer makes chat and calls public**
with invite-only registration; see [router setup](docs/networking.md#port-forwarding).

## Start Here

**[Follow the setup checklist](docs/installation.md)** — one guide from preparing
the server to opening your apps. Print it or tick off the steps as you go.

## Other documentation

The setup checklist above is the main guide. These references cover specific
topics and are ordered from common tasks to technical details:

1. [Router and DNS setup](docs/networking.md) — configure your domain, router,
    local DNS and remote WireGuard access.
2. [Operations and maintenance](docs/operations.md) — check services, manage
    updates, backups and optional features.
3. [Backup and recovery](docs/backup.md) — protect your data and recover files
    or rebuild a server.
4. [Troubleshooting](docs/troubleshooting.md) — diagnose common service and
    browser problems.
5. [Downloads and Jellyfin](docs/qbittorrent.md) — set up qBittorrent, its
    optional VPN and media libraries.
6. [Access and privacy](docs/security.md) — understand private access and
    protect credentials, profiles and recovery kits.
7. [Password vault sharing](docs/keepass-sharing.md) — manage separate
    administrator, family and personal vault access.
8. [Add-on integration](docs/addons.md) — lifecycle, backup and private
    configuration contracts for separately installed extensions.
9. [Independent DNS and shared HTTPS edge](docs/infrastructure.md) — host
    DNS and route web traffic when DEN shares a public IP with another server.
10. [Technical reference](docs/architecture.md) — review DEN's components,
    paths, storage and release behavior.
11. [Testing and validation](docs/testing.md) — see validation status and run
    contributor checks.

**Version 1.2.0 — focused core with separate add-ons.** Deployed and
tested on bare-metal Fedora Server. See [validation status](docs/testing.md#validation-status) for
what was checked and what remains.
For contributors, see the [technical reference](docs/architecture.md) and
[testing and validation](docs/testing.md).

## License

- Software: MIT License — [LICENSE](LICENSE)
- Documentation: CC BY 4.0 — [LICENSE-docs](LICENSE-docs)

Free to use, adapt and self-host.
