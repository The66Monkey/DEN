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

**Optional:** qBittorrent for downloads, Fluxer for chat and calls, and a
KeePassXC-compatible password vault.

Everything runs on one Fedora Server PC. Photos, files, media, Git and downloads
stay on your home network/VPN. **Enabling Fluxer makes chat and calls public**
with invite-only registration; see [router setup](docs/networking.md#port-forwarding).

## Start Here

**[Follow the setup checklist](docs/installation.md)** — one guide from preparing
the server to opening your apps. Print it or tick off the steps as you go.

## When You Need Help

- [Troubleshooting](docs/troubleshooting.md)
- [Downloads in Jellyfin](docs/qbittorrent.md)
- [Updates and maintenance](docs/operations.md)
- [Backup and recovery](docs/backup.md)
- [Access and privacy](docs/security.md)

**Version 1.0.0 — first home-server release.** Deployed and tested on bare-metal
Fedora Server. See [validation status](docs/testing.md#validation-status) for
what was checked and what remains. Keep another copy of files you cannot replace.
For contributors: [architecture](docs/architecture.md) and [testing](docs/testing.md).

## License

- Software: MIT License — [LICENSE](LICENSE)
- Documentation: CC BY 4.0 — [LICENSE-docs](LICENSE-docs)
- Attribution guidance: [ATTRIBUTION.md](ATTRIBUTION.md)

Free to use, adapt and self-host. A mention of the DEN Framework by
[ScandinavianHacking](https://scandinavianhacking.se/) is appreciated.
