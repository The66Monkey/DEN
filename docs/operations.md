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

## Forgejo Git access

DEN defaults to **HTTPS Git**, with Forgejo SSH disabled and no Git SSH port
published. Create the first account with `sudo den git-admin`, then copy the
HTTPS clone URL from the repository. For HTTPS pushes, use a Forgejo access
token through your Git credential manager; do not put tokens in clone URLs,
shell history or project files.

The host's port 22 is Fedora administration, not Forgejo. Adding a key under
Forgejo **Settings > SSH / GPG Keys** does not by itself enable Git SSH.
When SSH is enabled, DEN advertises `git.YOUR-DOMAIN`, not `localhost`; the
advertised hostname alone does not provide a network path into the container.

### Optional Git SSH through an existing administrative connection

An administrator can opt in without publishing another port. Merge this into
`/opt/den/private/compose-custom.yml` (create it root-owned, mode 0600 if absent;
preserve any existing settings):

```yaml
services:
  forgejo:
    environment:
      FORGEJO__server__DISABLE_SSH: 'false'
```

Validate the complete composition and recreate **only Forgejo** during a brief
maintenance window. Use the same Compose files as the deployment: base
`/opt/den/compose.yml`, the DNS/external-edge overlays if enabled, and all
existing private custom/add-on overlays. For an otherwise standard deployment:

```bash
sudo docker compose --project-name den --project-directory /opt/den \
  --env-file /opt/den/.env -f /opt/den/compose.yml \
  -f /opt/den/private/compose-custom.yml config --quiet
sudo docker compose --project-name den --project-directory /opt/den \
  --env-file /opt/den/.env -f /opt/den/compose.yml \
  -f /opt/den/private/compose-custom.yml up -d --no-deps forgejo
```

Do not edit generated `/opt/den/compose.yml` for persistent customization.
The private override is retained and validated during DEN updates, and included
in deployment backups. This opt-in does not require BASM, another VM, or a
shared public edge.

Register the workstation's **public** key in Forgejo. Never upload its private
key. An SSH-capable workstation can then use a private `~/.ssh/config` alias
like the following, replacing the uppercase placeholders locally:

```sshconfig
Host den-git
  HostName git.YOUR-DOMAIN
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  HostKeyAlias den-forgejo
  UserKnownHostsFile ~/.ssh/known_hosts_den_forgejo
  StrictHostKeyChecking yes
  ProxyCommand ssh -o BatchMode=yes -o StrictHostKeyChecking=yes ADMIN@DEN-HOST sudo -n docker compose --project-name den --project-directory /opt/den --env-file /opt/den/.env -f /opt/den/compose.yml exec -T forgejo nc 127.0.0.1 22
```

This uses two separate authentications: the outer connection is to DEN's
administrator account; the inner connection authenticates the workstation key
to Forgejo. It does not forward the SSH agent. It requires a working noninteractive
administrative SSH connection and permission to execute the shown Docker command.
Docker access is root-equivalent; do not grant it to ordinary Git users just
to enable this method. Other users should use HTTPS or a separately designed
restricted SSH transport.

After verifying DEN's host key through a trusted channel, obtain the container's
public SSH host key over that administrative connection:

```bash
sudo docker compose --project-name den --project-directory /opt/den \
  --env-file /opt/den/.env -f /opt/den/compose.yml \
  exec -T forgejo cat /data/ssh/ssh_host_ed25519_key.pub
```

On the workstation, put its algorithm and key after `den-forgejo` in
`~/.ssh/known_hosts_den_forgejo`, for example
`den-forgejo ssh-ed25519 VERIFIED-PUBLIC-HOST-KEY`, and make the file mode 0600.
Do not disable host-key checking or accept an unverified scan. Then verify:

```bash
ssh -T den-git
git ls-remote git@den-git:OWNER/REPOSITORY.git
```

Forgejo's greeting identifies the registered user/key and says shell access is
unavailable; Git operations should work. A copied web-interface SSH URL does
not include this local alias: use `git@den-git:OWNER/REPOSITORY.git` on this
workstation. Keep actual hostnames, addresses, usernames, keys and SSH aliases
in private operator configuration, never the public DEN repository.

## Cockpit administration

Open **Server administration - Cockpit** on the home page, or
`https://server.YOUR-DOMAIN/`. Use your Fedora login; administrative actions
retain Fedora's permission checks. Cockpit provides host storage, networking,
system services, logs and updates. DEN backups and coordinated service upgrades
remain `sudo den backup` and `sudo den auto-update`.

New installs and recovery enable integration by default. For an existing install,
update DEN, add the exact AdGuard/LAN DNS rewrite
`server.YOUR-DOMAIN → SERVER-LAN-IP`, then run:

```bash
sudo den cockpit-setup
```

DEN installs Cockpit and its Software Updates component, enables its socket,
configures the HTTPS origin and uses a verified private TLS backend. Standalone
and infrastructure proxies receive the backend CA; VPN DNS and DDNS are updated.
deSEC token permissions must include
`server` and `_acme-challenge.server`. The existing certificate challenge method
applies; HTTP validation uses the normal TCP 80 forwarding.

Use Software Updates to inspect or manually apply Fedora package updates.
Do not enable a separate automatic update schedule there while DEN's monthly
maintenance is enabled: it would bypass DEN's backup and health checks and
could reboot during a DEN operation.

To opt out, set `COCKPIT_ENABLED=no` in `/opt/den/.env` and run the same command.
DEN removes the route, link and VPN DNS record and restores the pre-integration
Cockpit configuration/socket listener. It keeps Cockpit installed. Remove the
LAN rewrite and the public `server` A record if no longer used. Existing custom
socket overrides or subsequent edits to DEN-managed Cockpit files require
explicit reconciliation before applying changes.

Backend certificate/key state is retained under `/opt/den/private/cockpit-state`;
DEN's recovery kit includes it. The certificate lasts ten years; setup reports
near-expiry rather than bypassing verification. Replace `backend.crt` and
`backend.key` there together (CN and DNS SAN `den-cockpit`), then rerun setup.

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

Routine Fedora package updates remain automatic, but **Fedora major upgrades
are opt-in**, including on older configurations without the new setting.
For an approved major-upgrade window, set `FEDORA_MAJOR_UPGRADES=yes` in
`/opt/den/.env`, run `sudo den auto-update`, and return the switch to `no`
afterward. This allows only the next stable Fedora Server release, never a beta
or a skipped major. Do not leave the switch enabled unintentionally.

Before any major upgrade, verify an independent backup/recovery kit, console
access and a known-good kernel in the boot menu. Retain the supported NVIDIA
driver branch; do not erase packages or bypass Secure Boot/SELinux checks.
Checks before reboot cannot guarantee new-kernel behavior.

Five minutes after each boot, `den-boot-check.timer` verifies DEN health and
the private homepage over HTTPS with certificate validation. It waits for
Fedora's `akmods.service`, checks GPU readiness when a DEN+ power policy exists,
and retries DEN startup only if its unit failed. It makes at most three attempts
with 30-second pauses and never restarts healthy containers, rolls back
databases, or repeatedly reboots. Failure triggers the existing local alert.
A disabled/masked or manually stopped `den.service` is respected; the homepage
must return exactly HTTP 200. NAS availability belongs to the
optional DEN+ feature, not this core health requirement.

Inspect `journalctl -u den-boot-check.service -b` and
`/srv/den/cache/boot-verified` (boot ID and verification time). Run
`sudo systemctl start den-boot-check.service` for a manual check. If disabling
maintenance completely, stop this timer too. Reboot verification is recovery
assistance, not a substitute for testing a restore.

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

## Separate add-ons

AI chat, narration and their GPU power policy are maintained in the private
[DEN+ repository](https://git.scandinavianhacking.dedyn.io/The66Monkey/DEN-plus), with a separate
`den-plus` command and settings. Core DEN neither provisions them nor accepts
their configuration keys. See [add-on integration](addons.md) for lifecycle
and backup contracts. Do not update an older enhanced server without following
DEN+'s migration guide first.
