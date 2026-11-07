# DEN Setup Checklist

Work from top to bottom. Commands run on the server unless marked otherwise.
A fast primary drive and a separate backup drive are recommended; two HDDs are
fine. Print it if useful.

| Your details | Fill in |
| --- | --- |
| Fedora login | ________________________ |
| Server LAN IP, e.g. `192.168.1.10` | ________________________ |
| Home subnet, e.g. `192.168.1.0/24` | ________________________ |
| Public IPv4 (router's WAN address) | ________________________ |
| Domain, e.g. `example.net` | ________________________ |
| Certificate contact email | ________________________ |

## 1. Prepare the Server

- [ ] Use a PC with an x86-64-v2 CPU and at least 8 GB RAM (16 GB recommended).
  Use Ethernet if possible.
- [ ] In BIOS/UEFI, set **Restore on AC Power Loss** (or equivalent) to
  **Power On**, so the server starts automatically when power returns.
- [ ] Install [Fedora Server](https://fedoraproject.org/server/download/) on the **primary drive**. Enable SSH and create your login.
  Select **Cockpit** if offered; DEN installs it if missing. Integration is
  enabled by default; set `COCKPIT_ENABLED=no` in your settings to opt out.
- [ ] Reserve the server's LAN IP in your router so it does not change.
  For example, the router might be `192.168.1.1` and the server `192.168.1.10`,
  on subnet `192.168.1.0/24`. Use your own network's values, not the router's
  address for the server.
- [ ] On your computer, connect with your Fedora login and the server IP:

  ```bash
  ssh YOUR-FEDORA-USER@SERVER-LAN-IP
  ```

### Media codecs and NVIDIA

The installer and recovery enable the third-party
[RPM Fusion Free](https://rpmfusion.org/) repository
and install its full `ffmpeg` package by default. If Fedora's `ffmpeg-free` is
present, DEN uses RPM Fusion's documented
`dnf swap ffmpeg-free ffmpeg --allowerasing` transaction. Review package
replacement/licensing requirements before installation. No nonfree GPU driver
repository or driver branch is installed automatically.

Jellyfin runs in a container with its own full `jellyfin-ffmpeg`; replacing host
FFmpeg does **not** replace that binary or fix container GPU access. Do not mount
the host FFmpeg executable into Jellyfin. See
[media diagnostics](operations.md#media-codecs-and-nvidia) before enabling
hardware acceleration.

DEN detects NVIDIA display/3D devices and checks `nvidia-smi` during installation,
recovery and `sudo den check`. A warning does not prevent software playback.
Keep a working GPU-compatible driver branch (including 580xx where appropriate).
DEN does not upgrade it, enroll Secure Boot keys or enable GPU passthrough.

## 2. Mount the Backup Drive

- [ ] Identify the backup drive's **existing filesystem and UUID**:

  ```bash
  lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS,MODEL
  ```

  If it has no filesystem, stop and get help preparing it. Formatting deletes
  its contents; DEN never formats disks.

- [ ] For an existing ext4 backup drive, create the mountpoint and edit `/etc/fstab`:

  ```bash
  sudo mkdir -p /mnt/den-backup
  sudo vi /etc/fstab
  ```

  Add this line using the drive's actual UUID. For XFS or Btrfs, use the matching
  filesystem type and options instead.

  ```text
  UUID=YOUR-BACKUP-UUID /mnt/den-backup ext4 defaults,nofail 0 2
  ```

- [ ] Mount it and confirm the correct disk appears:

  ```bash
  sudo mount /mnt/den-backup
  findmnt /mnt/den-backup
  ```

- [ ] Reboot with `sudo reboot`, reconnect over SSH, and check `findmnt` again.

## 3. Set Up DNS and the Router

- [ ] Add your domain at [deSEC](https://desec.io). If registered elsewhere,
  follow deSEC's nameserver instructions without removing records you still use.
- [ ] Create these **A records**, each pointing to your router's **public IPv4**:
  `vpn`, `home`, `media`, `photos`, `files`, `git`.
  Add `server` for the default Cockpit integration.
  Add `downloads` for qBittorrent and `chat` for Fluxer if wanted.
  Do not add AAAA records for DEN names.
- [ ] Create a deSEC API token with permission to update those records and
  create/delete certificate challenge TXT records. Keep it ready for installation.
- [ ] Forward **UDP 41873** to the server's LAN IP. Choose UDP, not TCP.
  With DNS certificates (`dns-desec`) and Fluxer disabled, no web forwards are needed.
- [ ] **If enabling Fluxer:** also forward **TCP 443, TCP 7881 and UDP 7882**
  directly to DEN. Chat and calls are public; other apps stay private.
  TCP 443 cannot simultaneously point to another server on the same public IP.
  If it already serves BASM, postpone public Fluxer until you plan the cutover;
  this setup does not configure a shared external proxy.
- [ ] Confirm your ISP gives you a reachable public IPv4. If the router is
  behind CGNAT, ask your ISP before continuing.

Use WireGuard below for correct DNS and private access. To use LAN devices
without VPN, optionally point each app's local DNS name to the server's LAN IP.
Keep `home.DOMAIN` pointing to the public IP.

## 4. Install DEN

- [ ] Get the DEN checkout onto the server. If Git access is configured:

  ```bash
  git clone git@github.com:The66Monkey/DEN.git
  cd DEN
  ```

  If you already have the checkout, just enter its directory.

- [ ] Copy and edit the settings:

  ```bash
  cp config/example.env /tmp/den.env
  vi /tmp/den.env
  ```

  Set these values, using your details above. Do not quote values:

  ```text
  DOMAIN=example.net
  EMAIL=you@example.net
  LAN_IP=192.168.1.10
  LAN_CIDR=192.168.1.0/24
  ACME_CHALLENGE=dns-desec
  MEDIA_MOUNT=/mnt/den-backup
  BACKUP_MOUNT=/mnt/den-backup
  ALLOW_SHARED_MEDIA_BACKUP=yes
  ```

  This shares the drive between media and snapshots: drive failure loses both.
  Photos and Nextcloud files stay on the primary drive. For separate media/backup disks,
  use different mountpoints and leave `ALLOW_SHARED_MEDIA_BACKUP=no`.

- [ ] Set optional services to `yes` or leave them `no`:
  `QBITTORRENT_ENABLED`, `FLUXER_ENABLED`, `KEEPASS_ENABLED`.
  Fluxer is public when enabled, including when upgrading an existing install.
  AI, narration and optional GPU power policy belong to the separate
  [DEN+ add-on](addons.md), not core settings.
- [ ] Leave `TV_CIDR` empty for the normal home-LAN setup. For a separate TV
  Wi-Fi network with Jellyfin, follow the
  [TV network setup](networking.md#optional-balanced-iot-protection) after
  installing DEN's independent AdGuard infrastructure.
- [ ] Make sure root can read the configured `UPDATE_REPOSITORY` without prompts.
  A private repository needs a read-only deploy key for root; your normal
  user's Git access is not enough.
- [ ] During setup, choose a server hostname when prompted (the suggested name is
  `FedoraDEN`; press Enter to accept it).
- [ ] Install, entering your Fedora password and deSEC token when asked:

  ```bash
  sudo bash install.sh /tmp/den.env
  ```

  The installer displays a grouped summary of the hostname, network, storage,
  optional services and automatic updates before installing packages or services.
  Enter `A` to accept, `R` to restart the review, or `C` to cancel.
  To change file-based
  choices, select `R`, edit the settings file in another terminal, save it, then
  press Enter to reload it and repeat validation and the hostname prompt.
  The deSEC token is requested after acceptance.

  On an interactive terminal, the visible screen is cleared for the review;
  redirected output stays plain text. Automated installs retain their existing
  behavior: the summary is printed without a confirmation prompt, and a private
  `DESEC_TOKEN_FILE` is still required. No extra command-line flag is needed.

  Leave SSH open. Downloads and certificates can take several minutes.
  SSH logins show a short DEN banner with the hostname, LAN IPv4 address, and
  service state. Run `sudo den status` for the detailed stack summary.
  If installation fails, use
  [troubleshooting](troubleshooting.md).

## 5. Connect with WireGuard

Each device needs a unique **lowercase** profile name. Keep profiles and QR codes private.
Skip `vpn-add` if that profile already exists.

### Connect Your Phone with WireGuard

- [ ] Install the [WireGuard app](https://www.wireguard.com/install/) on your phone.
- [ ] In your server SSH session, create and display its profile:

  ```bash
  sudo den vpn-add phone
  sudo sh -c 'qrencode -t ansiutf8 < /opt/den/private/phone.conf'
  ```

- [ ] In WireGuard, choose **Add tunnel / Scan from QR code** and scan the terminal.
  Activate the tunnel. Turn phone Wi-Fi off to test away-from-home access.

### Import WireGuard on Another Computer

- [ ] In your server SSH session:

  ```bash
  sudo den vpn-add laptop
  sudo install -o "$(id -un)" -m 600 /opt/den/private/laptop.conf "$HOME/laptop.conf"
  exit
  ```

- [ ] On your own computer, download the profile and remove the temporary copy:

  ```bash
  scp YOUR-FEDORA-USER@SERVER-LAN-IP:laptop.conf .
  ssh YOUR-FEDORA-USER@SERVER-LAN-IP 'rm -- "$HOME/laptop.conf"'
  ```

- [ ] Import `laptop.conf` into WireGuard, activate it, then delete the downloaded file.

## 6. Open Your Apps

Use your domain in place of `DOMAIN`. Open **names, not the server IP**.
Start at `https://home.DOMAIN` for links to enabled services, SSH instructions
and the DEN README. This page is LAN/VPN-only; use WireGuard or router NAT
loopback as described in [local DNS setup](networking.md#router-and-local-dns).
Complete only the services you enabled:

| Done | Service | Open | First action |
| --- | --- | --- | --- |
| [ ] | Jellyfin | `https://media.DOMAIN` | Create admin; add `/media/movies`, `/media/tv` or `/media/music`. |
| [ ] | Immich | `https://photos.DOMAIN` | Create admin; connect the mobile app for photo uploads. |
| [ ] | Nextcloud | `https://files.DOMAIN` | Sign in as `admin` with the password below. |
| [ ] | Forgejo | `https://git.DOMAIN` | Run `sudo den git-admin` over SSH, then use HTTPS Git. Optional private Git SSH is documented in [operations](operations.md#forgejo-git-access). |
| [ ] | qBittorrent | `https://downloads.DOMAIN` | Sign in as `admin`; get temporary password below and set a permanent one. For torrent-only protection, [upload a provider WireGuard profile](qbittorrent.md#optional-torrent-vpn). |
| [ ] | Fluxer | `https://chat.DOMAIN` | Public chat/calls. Use setup token below to create admin; registration is invite-only. |

Retrieve credentials privately over SSH; run optional commands only if enabled:

```bash
sudo grep '^NEXTCLOUD_ADMIN_PASSWORD=' /opt/den/.env
sudo den logs qbittorrent
sudo rexctl --dir /opt/den/fluxer setup token
```

If Fluxer's first-admin browser setup says registration is closed, use the
[terminal setup workaround](troubleshooting.md). After setup, use its one-time
sign-in link privately and save the generated recovery kit off-server in secure
storage. Treat both as credentials; never paste them into chat or public logs.

- [ ] For downloaded movies, add `/downloads/complete` as a Jellyfin Movies library
  and scan it. Metadata stays in Jellyfin's settings; seeding files remain unchanged.
- [ ] If KeePass is enabled, export to a mounted USB and open it in
  [KeePassXC](https://keepassxc.org/):

  ```bash
  sudo den keepass-export /media/usb/den-credentials.kdbx
  sudo den keepass-password
  ```

  Keep the vault password separate from the exported file; record app password
  changes in the vault yourself.
  For one canonical server vault and separate family/personal databases, see
  [password sharing](keepass-sharing.md). The optional private share is a manual
  integration, not enabled by the installer.

## 7. Finish

- [ ] Over SSH, run `sudo den check`; open your enabled apps and try a file or playback.
- [ ] If names fail with VPN on, check that browser/device Secure DNS is not
  bypassing the VPN's DNS.
- [ ] Save settings and recovery password to a mounted USB if wanted:
  `sudo den recovery-kit /media/usb`. Keep it private.

**Done.** Backups run Tuesdays around 03:00; monthly updates may reboot the server.
Keep disks connected. When something fails, run `sudo den status` and
`sudo den check`. See [troubleshooting](troubleshooting.md) or
[recovery](backup.md) only when needed.
