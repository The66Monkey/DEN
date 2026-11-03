# Keep DEN Running

Open `https://home.YOUR-DOMAIN/` on your LAN or VPN for the start page,
headed **Welcome home to your DEN**, and links to your services.

Most maintenance is automatic. Connect over SSH when you need to check something:

```bash
sudo den status
sudo den check
sudo den logs nextcloud      # replace with the service you need
```

DEN checks health hourly. Problems appear in the system journal and may show
on SSH login; there are no email or phone alerts.
If another operation is running, wait for it to finish.

For passwords, use a single owner/admin vault and separate family/personal
vaults. See [KeePass sharing](keepass-sharing.md). Close a directly shared vault
before synchronization, upgrades or VPN profile creation.

## Hosting a BASM VM

A Fedora DEN host can also run a Debian BASM VM using KVM/libvirt and Cockpit
Machines. Keep distinct LAN addresses and deployment data. A wired bridge lets
the VM obtain its own LAN lease; reserve both addresses. Moving the host from
Wi-Fi to Ethernet may change its IP: review DEN's `LAN_IP`, generated private
DNS, firewall bindings and router reservations before restarting. Preserve
configuration backups; do not blindly replace addresses inside application data.

Keep addresses, hardware inventory, service logs and acceptance results in a
private operator record, not public project documentation. After migration,
retain the source disks for rollback without running duplicate application
writers. Treat third-party managed devices as untrusted: never give them DEN
secrets or home VPN profiles solely for IP-discovery heartbeats.

The production DEN runtime is Docker; production Podman/Quadlet
support and its data migration have not been implemented. Existing local
Podman templates do not make a production runtime switch safe.

If BASM owns public TCP 80/443, DEN Fluxer needs a coordinated ingress plan.
Keep each WireGuard instance's UDP forwarding separate. LiveKit voice uses
TCP 7881 and UDP 7882 on DEN.
Voice forwarding alone does not restore chat HTTPS. Review
[coexistence and public chat](networking.md#coexisting-with-another-web-server)
before enabling both publicly; shared ingress is not configured automatically.

Moving between
machines does not require replacing profiles or QR codes if the endpoint,
port, keys and peer addresses remain valid;
test each required device before retiring the old server. To enroll a new
device, use `sudo den vpn-add DEVICE-NAME` and follow the private profile/QR
instructions, rather than sharing one profile across devices.

DEN's backup does not automatically include a libvirt VM or BASM's guest
repository. BASM manages its own guest backups. Schedule Fedora host updates/reboots
around guest backups and availability requirements.

## Media codecs and NVIDIA

New installs/recovery use RPM Fusion Free's full host FFmpeg by default, not
Fedora's codec-limited `ffmpeg-free`. Existing deployments do not rerun package
installation on a DEN source update. To apply the same change explicitly:

```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
# If ffmpeg-free is installed:
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
# Otherwise:
sudo dnf install ffmpeg --allowerasing
rpm -q ffmpeg
ffmpeg -version
```

Jellyfin's bundled FFmpeg is independent of these host packages. Check the
actual container binary instead of assuming host codec availability:

```bash
sudo docker compose --env-file /opt/den/.env -f /opt/den/compose.yml exec -T jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -version
sudo docker compose --env-file /opt/den/.env -f /opt/den/compose.yml exec -T jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -decoders
nvidia-smi
```

Installation and `den check` warn if an NVIDIA display GPU has no working
`nvidia-smi`, and remind owners that driver availability is not container GPU
access. Check kernel-module/Secure Boot status and the supported legacy driver
branch before changing drivers. A GTX 970 cannot decode every modern codec in
hardware: keep unsupported formats on software decoding.

DEN's default Compose does not request NVIDIA GPU devices. NVIDIA acceleration
also requires NVIDIA Container Toolkit, explicit Jellyfin GPU access, SELinux-
compatible permissions and Jellyfin Dashboard hardware-acceleration settings.
Do not disable SELinux, use privileged containers or replace the bundled FFmpeg
to bypass setup errors. Confirm an actual transcode and its Jellyfin FFmpeg log,
not only `nvidia-smi` output. Software transcoding remains the default.

## Automatic Monthly Maintenance

On the first of each month, between 04:00 and 04:30 server time, DEN updates
itself, enabled Fluxer and Fedora. It takes backups and may reboot.
Keep the storage disk connected. Missed maintenance runs when the timer resumes.

**Fluxer exposure change:** applying the public-chat update to an enabled
Fluxer install makes chat/calls public and resets voice IP discovery. Review
[direct router forwarding and cutover](networking.md#public-chat-and-calls)
before updating; DEN does not migrate an existing BASM instance.

Check the schedule or recent results:

```bash
systemctl list-timers den-update.timer
journalctl -u den-update.service -n 50
```

To run it now:

```bash
sudo den auto-update
```

To disable automatic updates:

```bash
sudo systemctl mask --now den-update.timer
```

To enable them again:

```bash
sudo systemctl unmask den-update.timer
sudo systemctl enable --now den-update.timer
```

For a different schedule, use `sudo systemctl edit den-update.timer`:

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-15 04:00:00
```

Then run `sudo systemctl daemon-reload` and
`sudo systemctl restart den-update.timer`.

Update failures stop the job. See [troubleshooting](troubleshooting.md);
do not remove an `update-in-progress` marker just to retry.

## Stop Without Losing Data

```bash
sudo systemctl stop den-update.timer den-backup.timer den-check.timer den.service
sudo den stop
```

WireGuard stays available. To resume:

```bash
sudo systemctl start den.service den-backup.timer den-check.timer den-update.timer
```

Do not delete data folders or Docker volumes to fix an error.
For disk space and saved snapshots, see [backup and recovery](backup.md).
Release maintainers: see [update contracts](architecture.md#release-updates).

## Optional AI

See [private AI operations](ai.md) for `sudo den ai-setup`, `sudo den ai-status`,
model unload, workstation SSH tunnels, persistent NVIDIA power caps and lab migration.
