# Install DEN

## Before You Start

1. Install Debian **13 Stable**, with SSH and standard system utilities, without a desktop. DEN currently targets x86_64 only; it is not an ARM, LXC, or multi-server installer.
2. Use a CPU with x86-64-v2 support, usually from 2012 or later, at least 8 GB RAM, and preferably 16 GB and four cores. Immich alone recommends 8 GB. GPU transcoding is not configured; direct-play compatible media is the recommended path on old PCs.
3. Keep the OS, databases, and `/srv/den` on a local Linux filesystem with ownership support, ideally ext4 on SSD. Allow at least 40 GB for applications, plus room for files, photos, and media. DEN does not format disks or create RAID.
4. Mount a **separate physical backup disk** at `/mnt/den-backup` using a UUID entry in `/etc/fstab`. Mount it now and verify it stays mounted after reboot. An example entry, after formatting the disk yourself, is `UUID=YOUR-DISK-UUID /mnt/den-backup ext4 defaults,nofail 0 2`. DEN never formats or automatically mounts the disk, and refuses an unmounted destination. Different partitions of the same physical disk are not a disaster backup; DEN can detect different filesystems, not physical failure independence.
5. Complete [router and DNS setup](networking.md). A public domain, WAN IPv4, reachable TCP 80/443 and UDP 51820, and LAN DNS overrides are required. No domain, CGNAT, or an ISP blocking inbound ports means this deployment model is not suitable.

DEN enables Docker, WireGuard, IPv4 forwarding, VPN DNS, and systemd timers. It installs Debian packages, writes under `/opt/den`, `/srv/den`, `/etc/wireguard`, `/etc/systemd/system`, `/etc/sysctl.d`, and creates `/usr/local/bin/den`. Use a fresh machine, not one already hosting applications.

## Install

Obtain the DEN checkout using your repository's actual Git URL. No public remote is assumed by these instructions.

```bash
cd DEN
cp config/example.env /tmp/den.env
nano /tmp/den.env
sudo bash install.sh /tmp/den.env
```

Keep `KEY=value` values unquoted. The only settings are your domain, certificate contact email, reserved server IPv4, actual LAN subnet, and mounted backup path. The VPN uses `10.44.0.0/24`; containers use `172.30.44.0/24`. DEN rejects a LAN overlapping either.

DEN installs dependencies, generates unique passwords and VPN keys, pulls pinned images, starts applications, and takes the first backup. Leave SSH open. The first download and Nextcloud setup can take several minutes; the readiness wait is bounded at 15 minutes.

## Verify

```bash
sudo den status
sudo den check
systemctl list-timers 'den-*'
```

From another LAN device, visit the four URLs printed by installation. The browser must show a valid HTTPS certificate, not a certificate warning. Follow [first-evening setup](first-evening.md), create the initial accounts, and make a new backup. Test access from mobile data: without VPN each application must return **403**, and with VPN it must be usable.

Save a recovery kit on a different device before considering setup complete:

```bash
sudo den recovery-kit /media/recovery-usb
```

The destination must already exist on a mounted separate filesystem. Keep a second private off-site copy. The kit contains the Restic password; losing it and the server together makes encrypted backups unrecoverable.

## Interrupted Installation

DEN refuses to generate a second environment over an existing one. Do not delete `/opt/den/.env` to retry: applications may already have adopted its passwords. Resolve the problem using [troubleshooting](troubleshooting.md), then `sudo den start`. An interruption before the systemd units were installed requires inspecting the recorded state and completing the missing installation steps; automatic interrupted-install resume is not implemented in 0.1.0.