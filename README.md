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
3. **Set up DNS at [deSEC](https://desec.io).** Create an account and confirm
   your email. Add a domain you own, such as `example.net`; deSEC hosts DNS,
   it does not register that domain for you. At your domain registrar, replace
   the domain's nameservers with the ones deSEC supplies. In deSEC, create
   **A records** for subnames `home`, `media`,
   `photos`, `files`, and `git`. Give every record your router's **public WAN
   IPv4**, not Fedora's LAN IP. Set `DOMAIN=example.net` in DEN's config.
   Add `chat` or `downloads` only if enabling Fluxer or qBittorrent.
   [Step-by-step DNS example](docs/networking.md#desec-setup).
4. **Forward these ports in your router** to the reserved server IP, using the
   same external and internal port numbers:

   | Protocol | Port | Purpose |
   | --- | --- | --- |
   | TCP | 80 | HTTPS certificate issuance and renewal; leave open |
   | TCP | 443 | HTTPS application access |
   | UDP | 41873 | WireGuard remote access |

   **Do not forward SSH (22) or any other application ports.** CGNAT will not
   work: you need a reachable public IPv4 from your ISP. If the WAN IP changes,
   DEN's built-in deSEC updater refreshes its records every four hours.
   The installer asks for a deSEC API token; the domain apex is never changed.
5. **Make the application names work at home.** In your router's local DNS,
   point `media.YOUR-DOMAIN`, `photos.YOUR-DOMAIN`, `files.YOUR-DOMAIN`, and
   `git.YOUR-DOMAIN` to the reserved **LAN IP**; include optional names if enabled.
   Devices must use that local DNS. Keep `home.YOUR-DOMAIN` pointing to the
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

## Try DEN Locally First

On any Podman-capable Fedora machine, `bin/den-local up` starts a disposable,
HTTP-only copy of the apps with generated logins, and `bin/den-local test` checks
it. See [testing](docs/testing.md#one-command-local-test-stack). It is not the
production install.

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

## Project Status

**0.1.0: alpha, with passing automated CI.** Headless Fedora deployment,
HDD-backed media/downloads, encrypted backups, monthly automatic maintenance,
and optional Fluxer, qBittorrent and KeePass support are implemented.
The [USB handover guide](docs/handover.txt) is a template to complete for the
owner, not an automatically generated export.

The automated suite passes on GitHub's Ubuntu runner, including real encrypted
Restic backup/restore and mocked maintenance failure paths. Full Fedora Server
deployment, certificates, VPN/voice access, database recovery and unattended OS
upgrades still need the [live acceptance checks](docs/testing.md). Setup in
under one hour remains a goal, not a measured guarantee. Keep an independent
copy of irreplaceable data until your deployment's recovery has been tested.

See [architecture and storage](docs/architecture.md), [security](docs/security.md), and [troubleshooting](docs/troubleshooting.md).