# DEN Setup Checklist

Work from top to bottom. Commands run on the server unless marked otherwise.
This guide uses an SSD for apps/settings and one HDD for media and snapshots.
Print it if useful; do not write passwords or tokens on it.

| Your details | Fill in |
| --- | --- |
| Fedora login | ________________________ |
| Server LAN IP, e.g. `192.168.1.10` | ________________________ |
| Home subnet, e.g. `192.168.1.0/24` | ________________________ |
| Public IPv4 (router's WAN address) | ________________________ |
| Domain, e.g. `example.net` | ________________________ |
| Certificate contact email | ________________________ |

## 1. Prepare the Server

- [ ] Use a PC with an x86-64-v2 CPU, at least 8 GB RAM (16 GB recommended),
  an SSD and a larger HDD. Use Ethernet if possible.
- [ ] Install Fedora Server on the **SSD only**. Enable SSH and create your login.
- [ ] Reserve the server's LAN IP in your router so it does not change.
  For example, the router might be `192.168.1.1` and the server `192.168.1.10`,
  on subnet `192.168.1.0/24`. Use your own network's values, not the router's
  address for the server.
- [ ] On your computer, connect with your Fedora login and the server IP:

  ```bash
  ssh YOUR-FEDORA-USER@SERVER-LAN-IP
  ```

## 2. Mount the HDD

- [ ] Identify the HDD's **existing filesystem and UUID**:

  ```bash
  lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS,MODEL
  ```

  If it has no filesystem, stop and get help preparing it. Formatting deletes
  its contents; DEN never formats disks.

- [ ] For an existing ext4 HDD, create the mountpoint and edit `/etc/fstab`:

  ```bash
  sudo mkdir -p /mnt/den-backup
  sudo vi /etc/fstab
  ```

  Add this line using the HDD's actual UUID. For XFS or Btrfs, use the matching
  filesystem type and options instead.

  ```text
  UUID=YOUR-HDD-UUID /mnt/den-backup ext4 defaults,nofail 0 2
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
  `home`, `media`, `photos`, `files`, `git`.
  Add `downloads` for qBittorrent and `chat` for Fluxer if wanted.
  Do not add AAAA records for DEN names.
- [ ] Create a deSEC API token with permission to update those records and
  create/delete certificate challenge TXT records. Keep it ready for installation.
- [ ] Forward **UDP 41873** to the server's LAN IP. Choose UDP, not TCP.
  This checklist uses DNS certificates (`dns-desec`), so no TCP web forwards
  are needed. Leave any other server's TCP 80/443 forwards alone.
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

  This shares the HDD between media and snapshots: HDD failure loses both.
  Photos and Nextcloud files stay on SSD. For separate media/backup disks,
  use different mountpoints and leave `ALLOW_SHARED_MEDIA_BACKUP=no`.

- [ ] Set optional services to `yes` or leave them `no`:
  `QBITTORRENT_ENABLED`, `FLUXER_ENABLED`, `KEEPASS_ENABLED`.
- [ ] Make sure root can read the configured `UPDATE_REPOSITORY` without prompts.
  A private repository needs a read-only deploy key for root; your normal
  user's Git access is not enough.
- [ ] Install, entering your Fedora password and deSEC token when asked:

  ```bash
  sudo bash install.sh /tmp/den.env
  ```

  Leave SSH open. Downloads and certificates can take several minutes.
  If installation fails, do not delete settings to retry; use
  [troubleshooting](troubleshooting.md).

## 5. Connect with WireGuard

Each device needs a unique **lowercase** profile name. Keep profiles and QR codes private.
Skip `vpn-add` if that profile already exists.

### Connect Your Phone with WireGuard

- [ ] Install the WireGuard app on your phone.
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
Complete only the services you enabled:

| Done | Service | Open | First action |
| --- | --- | --- | --- |
| [ ] | Jellyfin | `https://media.DOMAIN` | Create admin; add `/media/movies`, `/media/tv` or `/media/music`. |
| [ ] | Immich | `https://photos.DOMAIN` | Create admin; connect the mobile app for photo uploads. |
| [ ] | Nextcloud | `https://files.DOMAIN` | Sign in as `admin` with the password below. |
| [ ] | Forgejo | `https://git.DOMAIN` | Run `sudo den git-admin` over SSH, then use HTTPS Git. |
| [ ] | qBittorrent | `https://downloads.DOMAIN` | Sign in as `admin`; get temporary password below and set a permanent one. |
| [ ] | Fluxer | `https://chat.DOMAIN` | Use setup token below to create admin; registration is invite-only. |

Retrieve credentials privately over SSH; run optional commands only if enabled:

```bash
sudo grep '^NEXTCLOUD_ADMIN_PASSWORD=' /opt/den/.env
sudo den logs qbittorrent
sudo rexctl --dir /opt/den/fluxer setup token
```

- [ ] For downloaded movies, add `/downloads/complete` as a Jellyfin Movies library
  and scan it. Metadata stays in Jellyfin's settings; seeding files remain unchanged.
- [ ] If KeePass is enabled, export to a mounted USB and open it in KeePassXC:

  ```bash
  sudo den keepass-export /media/usb/den-credentials.kdbx
  sudo den keepass-password
  ```

  Keep the password separate; record app password changes in the vault yourself.

## 7. Finish

- [ ] Over SSH, run `sudo den check`; open your enabled apps and try a file or playback.
- [ ] If names fail with VPN on, check that browser/device Secure DNS is not
  bypassing the VPN's DNS.
- [ ] Save settings and recovery password to a mounted USB if wanted:
  `sudo den recovery-kit /media/usb`. Keep it private.

**Done.** Backups run nightly around 03:00; monthly updates may reboot the server.
Keep disks connected. When something fails, run `sudo den status` and
`sudo den check`. See [troubleshooting](troubleshooting.md) or
[recovery](backup.md) only when needed.
