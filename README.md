# DEN

**Digital Environment for Networking. A home server you can deploy in an evening.**

DEN deploys a fixed core stack on one Fedora Server PC: media, photos, files, private remote access, Git, and encrypted backups. Fluxer chat and a KeePassXC-compatible credential vault are optional. DEN takes the Bash-and-Compose approach of BASM and focuses it on home users rather than business infrastructure.

| Outcome | DEN's choice | Address |
| --- | --- | --- |
| Watch your media | Jellyfin | `https://media.your-domain` |
| Browse and back up phone photos | Immich | `https://photos.your-domain` |
| Sync and share household files | Nextcloud | `https://files.your-domain` |
| Reach home while away | WireGuard | One profile per device |
| Keep code and small projects | Forgejo | `https://git.your-domain` |
| Chat with household and friends (optional) | Fluxer | `https://chat.your-domain` |
| Recover from a broken disk | Restic | Separate encrypted backup disk |
| Check the basics | `den status` / `den check` | Terminal and systemd journal |

Traefik configures HTTPS automatically. Docker Compose runs the core applications; optional Fluxer is managed by its upstream `rexctl` tool. Core data and Fluxer recovery archives live under `/srv/den`; Fluxer's live Docker volumes remain in Docker's data root. Apps are restricted to your LAN and VPN, not the open internet. Public links remain household/VPN-only.

## Start Here

You need the current Fedora Server release on a 64-bit PC with x86-64-v2 CPU support, at least 8 GB RAM (16 GB recommended), an SSD, a separate mounted backup disk, a domain, and an internet connection that permits inbound ports. CGNAT is not supported. [Prepare the router](docs/networking.md) before installing.

From this checkout:

```bash
cp config/example.env /tmp/den.env
nano /tmp/den.env
sudo bash install.sh /tmp/den.env
```

There are five required settings and two optional feature switches, with no application-selection wizard. Read the [short installation guide](docs/installation.md), then [finish your accounts and start using DEN](docs/first-evening.md).

## Everyday Commands

```bash
sudo den status
sudo den check
sudo den backup
sudo den vpn-add phone
sudo den logs nextcloud
sudo den fluxer-status
```

Backups run nightly at about 03:00, briefly stopping the stack for a consistent snapshot. Updates are deliberately manual: apply a reviewed DEN release, after an automatic pre-update backup. [Maintenance](docs/operations.md) and [backup and recovery](docs/backup.md) cover the practical procedures.

## Boundaries

DEN values simplicity over flexibility, boring technology over novelty, and recovery over failover. It does not support Kubernetes, clusters, high availability, arbitrary extra applications, mail hosting, or enterprise operations. KeePass is an optional generated encrypted vault, not a server or browser app. Fluxer is optional and separately managed by `rexctl`, with its full backups included in DEN's Restic snapshots. Do not forward Fluxer's voice ports to the internet. No container auto-updater, public admin dashboard, Git SSH port, or CI runner is installed. Forgejo is the basic development tool; users write code on their own devices.

## Project Status

**0.1.0: initial implementation, not yet certified for production.** The target is a fresh server to usable applications in under one hour, assuming DNS/router/storage preparation is complete. This time budget is a goal, not a measured guarantee. Initial account setup remains in the applications' own interfaces.

Automated checks cover config rejection, secret permissions, Compose routing and image pins, optional Fluxer route/backup contracts, KeePass vault behavior, backup failure paths, and a real encrypted Restic backup/verified restore. Live Fedora boot, Wi-Fi firmware, database recovery, Fluxer voice networking, certificates, device VPN connections, and the one-hour experience still require the [acceptance checklist](docs/testing.md). Do not entrust your only copy of family photos to an unverified deployment.

See [architecture and storage](docs/architecture.md), [security](docs/security.md), and [troubleshooting](docs/troubleshooting.md).