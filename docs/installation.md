# Install DEN

## Before You Start

1. Install the current Fedora Server release on the **smaller primary SSD**, with SSH and standard system utilities. Select only that disk in Fedora's installer; leave the larger secondary HDD untouched. No desktop or server-side browser is needed: run the commands below at the text console or over SSH, and open application pages on another LAN/VPN device. Fedora Workstation is useful for development checks but is not the production acceptance target. DEN currently targets x86_64 only; it is not an ARM, LXC, or multi-server installer.
2. Use a CPU with x86-64-v2 support, usually from 2012 or later, at least 8 GB RAM, and preferably 16 GB and four cores. Immich alone recommends 8 GB. Fluxer is sized for the machine but adds meaningful memory and storage load; 16 GB is recommended when enabled. GPU transcoding is not configured; direct-play compatible media is the recommended path on old PCs.
3. Keep the OS, databases, app settings and caches on the SSD. Mount a local ext4, XFS or Btrfs filesystem on the **larger HDD** at `/mnt/den-storage` using its UUID in `/etc/fstab` (see below). The example sets `MEDIA_MOUNT=/mnt/den-storage`: DEN scripts persistent bind mounts from its `den/media` and `den/downloads` folders to `/srv/den/media` and `/srv/den/downloads`. Jellyfin's read-only `/media` and qBittorrent's default completed/incomplete download paths therefore use the HDD automatically. Other data, including photos and Nextcloud files, remains on SSD; allow at least 40 GB plus room for those files. Fluxer needs another 20 GB free when enabled. DEN does not format disks, choose disks by size, create RAID, or migrate existing files.
4. Choose backup storage: a separate disk, or the same HDD as media/downloads with `ALLOW_SHARED_MEDIA_BACKUP=yes`. For a shared HDD, set both `MEDIA_MOUNT` and `BACKUP_MOUNT` to `/mnt/den-backup`. Mount it persistently using its UUID in `/etc/fstab`, for example `UUID=YOUR-DISK-UUID /mnt/den-backup ext4 defaults,nofail 0 2`. DEN never formats the disk and refuses an unmounted destination.
5. Connect over Ethernet where practical. Fedora's newer kernel and firmware can improve support for older Wi-Fi hardware, but some USB adapters still need third-party kernel modules. DEN does not build or maintain out-of-tree Wi-Fi drivers; confirm the adapter works after a Fedora kernel update before relying on it as the server's only network connection.
6. Complete [router and DNS setup](networking.md). A public domain, WAN IPv4, reachable TCP 80/443 and UDP 41873, and LAN DNS overrides are required by default. If another server already uses public TCP 80/443, set `ACME_CHALLENGE=dns-desec` for DNS-01 certificates and forward only UDP 41873 for VPN-only remote access. No domain, CGNAT, or an ISP blocking the required inbound ports means this deployment model is not suitable.

DEN installs Docker CE and Compose from Docker's Fedora repository and Fedora packages for WireGuard, DNS, and backups. It keeps firewalld and SELinux enabled, opens the required host ports, and configures shared SELinux labels on container data. It writes under `/opt/den`, `/srv/den`, `/etc/wireguard`, `/etc/systemd/system`, `/etc/sysctl.d`, and creates `/usr/local/bin/den`. Use a fresh machine, not one already hosting applications.

It also writes `/etc/den/network.nft` and a Docker service dependency on
`den-firewall.service`. The guard restricts outside access before Docker
port forwarding; LAN clients need no VPN. Existing Cockpit remains accessible
on TCP 9090 from LAN/VPN. See [network policy](networking.md#lanvpn-network-guard).

Sharing the media and backup HDD requires the explicit
`ALLOW_SHARED_MEDIA_BACKUP=yes` opt-in; see
[storage choices](qbittorrent.md#sharing-the-media-and-backup-hdd).

## Prepare the Larger Disk Without a GUI

Inspect disks and existing filesystems from the console/SSH:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS,MODEL
sudo blkid
sudo mkdir -p /mnt/den-storage
sudo vi /etc/fstab
```

Identify the intended HDD by size **and model**, and its data partition by UUID;
do not assume it is `/dev/sdb`. If it has no suitable Linux filesystem, prepare
one yourself only after saving its existing contents elsewhere. Formatting
destroys data and is deliberately not scripted by DEN. For an existing ext4
filesystem, add this entry using the actual UUID:

```text
UUID=YOUR-HDD-PARTITION-UUID /mnt/den-storage ext4 defaults,nofail 0 2
```

Use the matching filesystem type/options for XFS or Btrfs. `nofail` lets the
headless OS boot for SSH repair if the HDD is absent; DEN's Docker dependency
still requires the disk before applications can start. Then:

```bash
sudo mount /mnt/den-storage
findmnt /mnt/den-storage
```

Verify after reboot before installing DEN. For the shared-HDD layout, use
`/mnt/den-backup` instead of `/mnt/den-storage` in these examples.

The installer creates systemd bind-mount units and a Docker storage dependency.
They survive reboots; Docker cannot start its auto-restarting containers before
these mounts are ready. DEN startup, health checks and backups fail explicitly
if the HDD or either bind mount is missing instead of silently filling the SSD.
`den check` checks free space on both filesystems.

For an intentional single-disk host, set `MEDIA_MOUNT=`. Older generated
environments without the setting retain single-disk behavior; changing an
existing environment does not move data. Use a reviewed offline migration, not
an in-place change of this setting.

## Install

Obtain the DEN checkout using your repository's actual Git URL. No public remote is assumed by these instructions.

```bash
cd DEN
cp config/example.env /tmp/den.env
vi /tmp/den.env
sudo bash install.sh /tmp/den.env
```

Keep `KEY=value` values unquoted. Required settings are your domain, certificate contact email, reserved server IPv4, actual LAN subnet, and mounted backup path. The installer will also prompt for a deSEC API token so it can keep DEN's DNS records current; create the records listed in [networking](networking.md) first. Set `KEEPASS_ENABLED=yes` to generate an optional KeePass-compatible credential vault, or `FLUXER_ENABLED=yes` to install optional Fluxer chat; both default to `no`. The VPN uses `10.44.0.0/24`; containers use `172.30.44.0/24`. DEN rejects a LAN overlapping either.

`sudo` prompts for your Fedora login password when needed; no permanent
passwordless sudo rule is required. The certificate email is your contact
address for Let's Encrypt; Let's Encrypt does not require an API token.
For automated SSH installs without an interactive token prompt, put only the
deSEC token in a root-owned, mode-600 regular file, then run:

```bash
sudo DESEC_TOKEN_FILE=/root/den-desec-token bash install.sh /tmp/den.env
```

The installer rejects missing, symlinked, publicly readable or invalid token
files. Delete the input file after installation; the installed updater keeps
its own protected copy under `/opt/den/private/ddns.env`. Do not put tokens in
Git, command-line arguments, or deployment logs.

Set `QBITTORRENT_ENABLED=yes` to add optional [qBittorrent downloads](qbittorrent.md);
it defaults to `no`. Configure `downloads.DOMAIN` in public and LAN DNS first.
Its HTTPS Web UI is LAN/VPN-only. No extra router ports or outbound VPN are
configured. Set a permanent application password immediately after first login.

DEN installs dependencies, generates unique passwords and VPN keys, pulls pinned images, starts applications, and takes the first backup. Leave SSH open. The first download and Nextcloud setup can take several minutes; the readiness wait is bounded at 15 minutes.

When Fluxer is enabled, its official `rexctl` manager is installed and configured behind Traefik at `chat.<DOMAIN>`. Keep the setup token printed during installation; use it to create the first administrator in a browser **on another device**, not on the headless server. Registration starts invite-only. DEN stores Fluxer's full archives under `/srv/den/fluxer/backups`, which are included in encrypted Restic snapshots. Fluxer's live media remains in its upstream-managed Docker object-store volume on SSD: `rexctl install` supports an external S3-compatible service, but not a local media-folder flag. DEN does not rewrite its managed Compose files or relocate Docker's entire data root; HDD-backed Fluxer live media is not automated. Fluxer voice is addressed to `LAN_IP`; clients need LAN or VPN access. Do not forward TCP 7881 or UDP 7882 from your router.

Monthly automatic updates and required reboots are enabled by default at 04:00
on the first day of each month. Configure noninteractive root Git access to
`UPDATE_REPOSITORY` before installing (a read-only deploy key for a private
repository). The installer checks it before initializing application data.
See [maintenance](operations.md) for schedule changes, opt-out, major migrations,
and the automatic stable Fedora release upgrade.

## Verify

```bash
sudo den status
sudo den check
systemctl list-timers 'den-*'
```

From another LAN device, visit the four URLs printed by installation. The browser must show a valid HTTPS certificate, not a certificate warning. Follow [first-evening setup](first-evening.md), create the initial accounts, and make a new backup. Test access from mobile data: without VPN, DEN applications and administration must be unreachable (normally dropped by the network guard). With VPN they must be usable. In DNS-01 coexistence mode, public HTTPS can reach your other server instead.

Save a recovery kit on a different device before considering setup complete:

```bash
sudo den recovery-kit /media/recovery-usb
```

The destination must already exist on a mounted separate filesystem. The kit contains the Restic password; keep it private and somewhere you can access if the server fails.

## Optional KeePassXC Vault

Set `KEEPASS_ENABLED=yes` in the install config before installing. DEN creates a KeePass-compatible encrypted database at `/opt/den/private/credentials.kdbx` with DEN-generated service credentials and WireGuard profiles. The master password is stored separately in `/opt/den/private/keepass-master-password`; both files are root-only and included in DEN recovery copies. KeePassXC is installed on your personal computer, not on the headless server.

Export the database to a mounted separate device, then retrieve the password through a separate secure channel:

```bash
sudo den keepass-export /media/usb/den-credentials.kdbx
sudo den keepass-password
```

Do not store the database and its password together. Keep another protected copy of both for recovery. After adding a VPN device, `sudo den keepass-sync` adds its profile without replacing existing vault entries. Update entries yourself if you change an application password outside DEN.

## Interrupted Installation

DEN refuses to generate a second environment over an existing one. Do not delete `/opt/den/.env` to retry: applications may already have adopted its passwords. Resolve the problem using [troubleshooting](troubleshooting.md), then `sudo den start`. An interruption before the systemd units were installed requires inspecting the recorded state and completing the missing installation steps; automatic interrupted-install resume is not implemented in 0.1.0.