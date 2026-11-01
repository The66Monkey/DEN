# DEN

**Digital Environment for Networking. A home server you can deploy in an evening.**

DEN deploys a fixed core stack on one Fedora Server PC: media, photos, files, private remote access, Git, and encrypted backups. Fluxer chat, qBittorrent downloads, and a KeePassXC-compatible credential vault are optional. DEN takes the Bash-and-Compose approach of BASM and focuses it on home users rather than business infrastructure.

## Quick Prep: Before Installing DEN

1. **Install Fedora Server** on the smaller SSD, with SSH enabled. Use Ethernet
   if possible. You need an x86-64-v2 PC, at least 8 GB RAM (16 GB recommended),
   and a separate backup disk. No desktop is needed.
2. **Lock the server's IP in your router.** Note the LAN IPv4 shown by Fedora
   Server (or run `hostname -I`). In your router's DHCP settings, reserve that
   address for the server's network adapter, for example `192.168.1.10`.
   This is `LAN_IP`; your home subnet, for example `192.168.1.0/24`, is `LAN_CIDR`.
3. **Set up DNS at [deSEC](https://desec.io).** Add your domain and, if using
   your own registered domain, set its nameservers at your registrar as deSEC
   instructs. Create **A records** for the domain itself and `media`, `photos`,
   `files`, and `git` beneath it, all pointing to your router's **public WAN
   IPv4**, not the server's LAN IP. Add `chat` or `downloads` only if enabling
   Fluxer or qBittorrent. Do not create AAAA records or use a CDN/proxy.
4. **Forward these ports in your router** to the reserved server IP, using the
   same external and internal port numbers:

   | Protocol | Port | Purpose |
   | --- | --- | --- |
   | TCP | 80 | HTTPS certificate issuance and renewal; leave open |
   | TCP | 443 | HTTPS application access |
   | UDP | 51820 | WireGuard remote access |

   **Do not forward SSH (22) or any other application ports.** CGNAT will not
   work: you need a reachable public IPv4 from your ISP. If the WAN IP changes,
   arrange a deSEC-compatible DDNS updater; DEN does not update public DNS.
5. **Make the application names work at home.** In your router's local DNS,
   point `media.YOUR-DOMAIN`, `photos.YOUR-DOMAIN`, `files.YOUR-DOMAIN`, and
   `git.YOUR-DOMAIN` to the reserved **LAN IP**; include optional names if enabled.
   Devices must use that local DNS. Keep the domain itself pointing to the
   public WAN IP for WireGuard. See [router and DNS details](docs/networking.md)
   if your router lacks local DNS overrides.
6. **Prepare storage.** Mount the larger data disk at `/mnt/den-storage` and a
   separate physical backup disk at `/mnt/den-backup`, persistently across
   reboots. DEN never formats disks. Follow the
   [disk preparation steps](docs/installation.md#prepare-the-larger-disk-without-a-gui);
   for a single-disk server, explicitly set `MEDIA_MOUNT=`.

Then [install DEN](#install-den) from the console or SSH on your home network.

| Outcome | DEN's choice | Address |
| --- | --- | --- |
| Watch your media | Jellyfin | `https://media.your-domain` |
| Browse and back up phone photos | Immich | `https://photos.your-domain` |
| Sync and share household files | Nextcloud | `https://files.your-domain` |
| Reach home while away | WireGuard | One profile per device |
| Keep code and small projects | Forgejo | `https://git.your-domain` |
| Chat with household and friends (optional) | Fluxer | `https://chat.your-domain` |
| Download and seed torrents (optional) | qBittorrent | `https://downloads.your-domain` |
| Recover from a broken disk | Restic | Separate encrypted backup disk |
| Check the basics | `den status` / `den check` | Terminal and systemd journal |

Traefik configures HTTPS automatically. Docker Compose runs the core applications; optional Fluxer is managed by its upstream `rexctl` tool. Fedora Server runs headlessly: install and administer DEN over SSH, and use application browsers on another device. The default example keeps the OS, databases, settings and caches on the small SSD, with Jellyfin media and qBittorrent downloads on a mounted larger HDD. Core data and Fluxer recovery archives remain accessible under `/srv/den`; Fluxer's live Docker volumes remain in Docker's data root. Apps are restricted to your LAN and VPN, not the open internet. Public links remain household/VPN-only.

## Install DEN

From this checkout:

```bash
cp config/example.env /tmp/den.env
vi /tmp/den.env
sudo bash install.sh /tmp/den.env
```

There are five required settings, a secondary-storage mount setting and three optional feature switches, with no application-selection wizard. Mount the larger disk at `MEDIA_MOUNT` before installing, or explicitly set `MEDIA_MOUNT=` for a single-disk host. DEN never selects, formats or partitions disks. Read the [short installation guide](docs/installation.md), then [finish your accounts and start using DEN](docs/first-evening.md). [Optional qBittorrent setup](docs/qbittorrent.md) covers its private Web UI, storage, and normal outbound connection.

## Everyday Commands

```bash
sudo den status
sudo den check
sudo den backup
sudo den vpn-add phone
sudo den logs nextcloud
sudo den fluxer-status
```

Backups run nightly at about 03:00. Monthly automatic maintenance runs on the
first day at 04:00 (plus up to 30 minutes of jitter): DEN releases, enabled
Fluxer, Fedora packages, and stable Fedora major upgrades, with backups and
automatic reboots when needed. Application/database majors follow release
migrations rather than arbitrary image tags. [Maintenance](docs/operations.md)
explains the default schedule and how to change or disable it.

## Boundaries

DEN values simplicity over flexibility, boring technology over novelty, and recovery over failover. It does not support Kubernetes, clusters, high availability, arbitrary extra applications, mail hosting, or enterprise operations. KeePass is an optional generated encrypted vault, not a server or browser app. Fluxer is optional and separately managed by `rexctl`, with its full backups included in DEN's Restic snapshots. Do not forward Fluxer's voice ports to the internet. No blind image-tag auto-updater, public admin dashboard, Git SSH port, or CI runner is installed. Forgejo is the basic development tool; users write code on their own devices.

## Project Status

**0.1.0: initial implementation, not yet certified for production.** The target is a fresh server to usable applications in under one hour, assuming DNS/router/storage preparation is complete. This time budget is a goal, not a measured guarantee. Initial account setup remains in the applications' own interfaces.

Automated checks cover config rejection, secret permissions, Compose routing and image pins, optional Fluxer route/backup contracts, KeePass vault behavior, backup failure paths, and a real encrypted Restic backup/verified restore. Live Fedora boot, Wi-Fi firmware, database recovery, Fluxer voice networking, certificates, device VPN connections, and the one-hour experience still require the [acceptance checklist](docs/testing.md). Do not entrust your only copy of family photos to an unverified deployment.

See [architecture and storage](docs/architecture.md), [security](docs/security.md), and [troubleshooting](docs/troubleshooting.md).