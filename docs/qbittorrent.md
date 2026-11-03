# Downloads and Jellyfin

## Enable qBittorrent

Before installation, set `QBITTORRENT_ENABLED=yes` and add the `downloads`
DNS name as described in [networking](networking.md).

Open `https://downloads.your-domain`. Sign in as `admin`; get the temporary
password over SSH:

```bash
sudo den logs qbittorrent
```

Set a permanent password in the Web UI immediately. Until then, restarting
changes the temporary password. Keep UPnP/NAT-PMP disabled and do not forward
torrent or Web UI ports. Only download material you have permission to share.

By default, trackers and peers see your normal public IP. DEN's **home-access**
WireGuard is not an outbound privacy VPN. For torrent-only protection, use the
separate optional provider tunnel below; other apps and home WireGuard stay unchanged.

## Optional Torrent VPN

Obtain a WireGuard `.conf` from a trusted VPN provider that permits BitTorrent.
Use **one peer**, a full IPv4 tunnel (`AllowedIPs = 0.0.0.0/0`, optionally also
`::/0`), and a **public IPv4 endpoint or provider hostname**.
Hostnames are resolved on DEN once during import and the selected public IPv4
address is saved privately. Re-import the original profile if the provider
changes its endpoint address; there is no runtime DNS/direct-traffic fallback.
Ask the provider for a supported profile if needed; do not guess an endpoint.
Hooks, scripts, custom routing and IPv6-only profiles are rejected.
Optional MTU must be 1280–1420.

### Copy the Profile Privately

On your computer (replace `admin` and `den-server` with your SSH login/hostname):

```bash
chmod 600 ~/Downloads/provider.conf
scp ~/Downloads/provider.conf admin@den-server:~/torrent-provider.conf
ssh admin@den-server
chmod 600 ~/torrent-provider.conf
sudo den torrent-vpn "$HOME/torrent-provider.conf"
```

Never paste the profile into chat, Git, an issue or a Web UI. Import reads it as
data, validates it, and saves an owner-only copy at
`/opt/den/private/torrent-vpn/wg0.conf`. After a successful import, remove the
upload from your SSH home (`rm -- ~/torrent-provider.conf`); retain a secure
off-server copy. Take a new encrypted backup with `sudo den backup`.
Profiles and the previous imported profile are included in private deployment
backups/recovery kits; restoring an old kit can restore an expired VPN key.

The command stops qBittorrent first, then recreates **only** its VPN sidecar and
qBittorrent. A tunnel startup failure does **not** enable direct traffic.
Repeat the same import command to change providers or rotate keys.

### Traffic and Availability

- Keep using **`https://downloads.your-domain`**, over LAN or your home VPN.
  The private HTTPS proxy remains in place; no additional host ports are opened.
- Torrent traffic uses a pinned Gluetun WireGuard sidecar with its firewall
  enabled. qBittorrent shares that network namespace, not DEN's normal network.
  There is no LAN-subnet outbound bypass. The sidecar resolver handles DNS
  through the tunnel instead of using Docker/host DNS; profile DNS is not used.
- IPv6 is deliberately blocked, including when a provider profile contains IPv6.
  Only IPv4 tunnel addresses/routes are imported. Provider port forwarding is
  not configured; do not enable UPnP/NAT-PMP.
- The VPN protects your normal public IP from torrent peers, **not anonymity**.
  You trust the provider; account activity and shared files may identify you.

To require protection **before** uploading the first profile:

```bash
sudo den torrent-vpn wait
```

This saves `QBITTORRENT_VPN_ENABLED=yes` and leaves qBittorrent stopped, including
across normal starts/reboots, until a profile is imported. The downloads URL is
unavailable during this waiting state; other DEN apps remain usable. For a new
installation, the same setting in your configuration enables this waiting mode.
`sudo den check` reports the missing profile as needing attention, even when the
other service checks pass.

Check `sudo den status` and `sudo den logs torrent-vpn`. After import, check a
legal torrent's peer-reported IP (or a trusted torrent IP-check service): it
must be the provider address, not your ISP address. A real provider handshake,
egress address and failure/restart test are required before relying on protection.
If the VPN container itself was replaced or restarted and downloads remain
offline, re-import the saved profile to recreate both containers together:
`sudo den torrent-vpn /opt/den/private/torrent-vpn/wg0.conf`.

To **explicitly** allow your normal public IP again:

```bash
sudo den torrent-vpn off
```

This saves `QBITTORRENT_VPN_ENABLED=no` and recreates qBittorrent on DEN's normal
network. It is never done automatically after a VPN failure.

## Watch Completed Downloads

In Jellyfin: **Dashboard → Libraries → Add Media Library**.
Choose Movies and add `/downloads/complete`, then scan.

For mixed media, use qBittorrent category folders such as
`/downloads/complete/movies` and `/downloads/complete/tv`; add separate Jellyfin
libraries for each.

Jellyfin reads completed files without modifying them, so seeding can continue.
Posters and metadata stay in its configuration. Leave options to save artwork
or NFO files beside movies disabled. Do not move seeding files outside qBittorrent.

| On the server | Inside qBittorrent |
| --- | --- |
| `/srv/den/downloads/complete` | `/downloads/complete` |
| `/srv/den/downloads/incomplete` | `/downloads/incomplete` |
| `/srv/den/qbittorrent` | `/config` |

Use `sudo den start`, `stop`, `status` and `logs qbittorrent` to manage it.
Settings and both download folders are included in nightly snapshots.

### Sharing the Media and Backup HDD

For one HDD holding media, downloads and snapshots:

```text
MEDIA_MOUNT=/mnt/den-backup
BACKUP_MOUNT=/mnt/den-backup
ALLOW_SHARED_MEDIA_BACKUP=yes
```

The HDD holds `den/media`, `den/downloads` and `den-restic`.
Apps/settings remain on SSD. Disk failure loses both media and its snapshots.

These are installation settings, not migration commands. Changing them on an
existing server does not move files; arrange an offline migration instead.
