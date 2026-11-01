# Verification

## Automated Checks

On a development machine with Bash, jq, OpenSSL, ShellCheck, Restic, and Docker Compose v2:

```bash
bash tests/run.sh
```

Tests need neither root nor a Docker daemon. `COMPOSE_BIN` and `RESTIC_BIN` optionally point to standalone validators. All fixtures live in temporary directories. The suite checks:

- Strict config, missing/unknown/duplicate keys, malformed/private IP ranges, overlapping subnets, and non-evaluated input.
- Unique generated secrets, root-only environment permissions, and refusal to regenerate an existing environment.
- Secondary-storage defaults and legacy single-disk compatibility; missing/wrong bind mounts, separate writable Linux filesystems, persistent mount-unit contracts and missing-media backup refusal.
- Exactly eleven core Compose services, plus one only when qBittorrent is enabled; only LAN-bound proxy ports, bind-mounted storage, digest-pinned images, readiness probes, and all private HTTPS routes.
- Cold backup ordering, saved deployment config, restarting previously running services, and failure propagation for Docker listing/stopping, Restic, restart, and missing backup disk.
- Explicit snapshot selection and rejection of existing, live-root, backup-root, and filesystem-root restore destinations.
- A real encrypted Restic repository, media and configuration restore with verification, cache exclusions, password rejection, and full repository-data checking.
- Per-device VPN addresses and keys, protected profiles, duplicate/name rejection, and persistent peer revocation (with mocked WireGuard).
- Optional KeePass vault creation, mode-600 files, generated credentials, WireGuard attachments, and non-destructive resynchronization.
- Optional Fluxer route privacy, Rexctl full-archive-before-Restic ordering, and the disabled-by-default upgrade path.
- Optional qBittorrent config validation, profile selection across lifecycle commands, private HTTPS routing, no published peer/UI ports, disabled port mapping, and preserved existing preferences.
- Update refusal after failed downloads/backups, preserved environment secrets, failed readiness reporting, staging cleanup, and Nextcloud major-version gates (with mocked Compose).
- Monthly timer, ordered release tags, backup/error gates, explicit database-major migration hooks, interrupted-update refusal, stable next-Fedora selection, and required reboots (mocked Git/DNF/systemd).

CI runs these same non-root tests. They validate the scripts and file-level backup contract, **not** the application containers' runtime behavior.

Where unprivileged user/mount namespaces are available, the suite also checks
real bind mounts, generated systemd/Docker dependencies and an encrypted
media/download restore across filesystems, with temporary mounts isolated from
the host. Otherwise that test prints an explicit skip. Actual Fedora boot
ordering and SELinux labels still require live acceptance: reboot a disposable
SSD/HDD host, verify both bind mounts precede Docker startup, then boot without
the HDD and confirm Docker/DEN do not write media or downloads onto SSD.

## Required Live Acceptance

### Local Rootless Podman Smoke Test

For a disposable LAN-only test on Fedora Workstation, a rootless Podman Quadlet
is provided at `templates/podman/den-jellyfin-local.container`. This is separate
from the production installer: HTTP only, no VPN, and no automated backups.
Additional Quadlets in the same directory run Immich, Nextcloud, and Forgejo.
Use test credentials and media, not private data. The same storage disk holds
both applications and their data; this is not a disaster backup.

The example assumes UID/GID 1000, LAN address `192.168.50.109`, and a writable
disk mounted at `/mnt/Storage`. Adjust these in your installed copy as needed;
reserve the LAN address before relying on it. Use a dedicated media directory,
since Podman applies SELinux labels to the mounted directories.

```bash
mountpoint /mnt/Storage
mkdir -p /mnt/Storage/den-local/jellyfin/{config,cache} /mnt/Storage/den-local/media
mkdir -p ~/.config/containers/systemd
cp templates/podman/den-jellyfin-local.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start den-jellyfin-local.service
curl --fail http://192.168.50.109:8096/health
```

Open `http://192.168.50.109:8096` and complete Jellyfin's first-user setup.
Add `/media` as the library path; put sample media in
`/mnt/Storage/den-local/media` on the host. Test playback from another LAN device.
If firewalld blocks access, add an incoming TCP 8096 rule restricted to your
actual LAN subnet in the interface's active zone; do not forward this port on
your router.

The Quadlet starts with the user systemd session, not necessarily at boot.
Production monthly maintenance is not installed for these local smoke-test
Quadlets; it would upgrade and reboot the shared host. Validate it on a
dedicated production acceptance machine before enabling it here.
Boot startup requires a persistent disk mount and administrator-enabled user
lingering. Stop it with `systemctl --user stop den-jellyfin-local.service`;
configuration and media remain on disk. Do not run this test alongside a
production Jellyfin deployment on the same port. This does not satisfy the
production acceptance checks below.

#### Expand to Photos, Files, and Git

The additional services use a private Podman network with no published database
or Redis ports. Nextcloud and Immich use separate Valkey containers.
Image digests match the production Compose template. Fluxer, KeePass, the
production proxy, WireGuard, and DEN's system timers are not installed.

Prepare directories and generate credentials **once**, before starting:

```bash
(
set -eu
mountpoint -q /mnt/Storage
mkdir -p /mnt/Storage/den-local/immich/{database,library,cache}
mkdir -p /mnt/Storage/den-local/nextcloud/{database,html} /mnt/Storage/den-local/forgejo
install -d -m 700 ~/.config/den-local
umask 077
for file in immich-db.env immich.env nextcloud-db.env nextcloud.env forgejo-admin.env; do
    test ! -e "$HOME/.config/den-local/$file"
done
immich_password=$(openssl rand -hex 24)
nextcloud_password=$(openssl rand -hex 24)
printf 'POSTGRES_PASSWORD=%s\n' "$immich_password" > ~/.config/den-local/immich-db.env
printf 'DB_PASSWORD=%s\n' "$immich_password" > ~/.config/den-local/immich.env
printf 'POSTGRES_PASSWORD=%s\n' "$nextcloud_password" > ~/.config/den-local/nextcloud-db.env
printf 'POSTGRES_PASSWORD=%s\nNEXTCLOUD_ADMIN_PASSWORD=%s\n' \
    "$nextcloud_password" "$(openssl rand -hex 24)" > ~/.config/den-local/nextcloud.env
printf 'FORGEJO_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)" > ~/.config/den-local/forgejo-admin.env
)
mkdir -p ~/.config/containers/systemd
cp templates/podman/den-local.network templates/podman/den-jellyfin-local.container \
    templates/podman/den-immich*.container templates/podman/den-valkey-local.container \
    templates/podman/den-nextcloud*.container templates/podman/den-forgejo-local.container \
    ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start den-immich-local.service den-nextcloud-local.service den-forgejo-local.service
```

Do not regenerate credentials over initialized databases. Keep these mode-600
files private and outside the checkout. Starting the apps also starts their
dependencies; database units wait for readiness. Initial image pulls and
Nextcloud installation may take several minutes.

After Nextcloud is installed, enable its separate cron container:

```bash
podman exec -u www-data den-nextcloud-local php occ background:cron
systemctl --user start den-nextcloud-cron-local.service
```

Create Forgejo's initial administrator once; public registration and Git SSH
are disabled:

```bash
(
set -eu
source ~/.config/den-local/forgejo-admin.env
podman exec -u git den-forgejo-local forgejo admin user create \
    --username denadmin --password "$FORGEJO_ADMIN_PASSWORD" \
    --email admin@den.invalid --admin --must-change-password
)
```

| Application | Local URL | Initial account |
| --- | --- | --- |
| Jellyfin | `http://192.168.50.109:8096` | First-run wizard |
| Immich | `http://192.168.50.109:2283` | First signup becomes admin |
| Nextcloud | `http://192.168.50.109:8080` | `admin`; password in `~/.config/den-local/nextcloud.env` |
| Forgejo | `http://192.168.50.109:3000` | `denadmin`; password in `~/.config/den-local/forgejo-admin.env` |

Test a photo upload and thumbnail, a Nextcloud upload/download, and an HTTP
Git push/clone using disposable fixtures. ML models download when first used.
Do not forward these ports on the router or reuse production passwords over
HTTP. The configured LAN IP can change unless reserved.

Inspect with `podman ps` and `journalctl --user -u den-nextcloud-local.service`.
Stop all test containers with:

```bash
systemctl --user stop den-jellyfin-local.service den-immich-local.service \
    den-immich-ml-local.service den-immich-db-local.service \
    den-nextcloud-cron-local.service den-nextcloud-local.service \
    den-nextcloud-db-local.service den-nextcloud-redis-local.service \
    den-forgejo-local.service den-valkey-local.service
```

Storage and credentials persist after stopping; no volumes are deleted.

qBittorrent is a separate opt-in local service; follow
[its setup guide](qbittorrent.md). The four-app setup above does not install it.
If enabled, stop it separately with
`systemctl --user stop den-qbittorrent-local.service`.

### Production Acceptance

Before marking a DEN release production-ready, use a fresh Fedora Server VM or dedicated PC and a separate backup disk. Set up a real domain and router as documented. Use non-sensitive fixtures. Fedora Workstation is suitable for development checks, but does not replace Server acceptance.

1. Time from running the installer to healthy applications. Record download speed, hardware, and first-user setup time; the under-one-hour goal is not validated by the unit tests.
2. Confirm each pinned image starts on the minimum CPU class, Nextcloud creates its account/database, Immich reaches its matched database and ML worker, and Forgejo admin creation works.
3. Open all four apps from a LAN client with valid public certificates. Check upload/download, movie playback, a photo thumbnail/search, Nextcloud desktop sync, and HTTPS Git clone/push.
4. Check TCP 80/443 bindings and UDP 51820. Scan from outside: application HTTPS must be 403 without VPN, and no database, SSH Git, DNS, or dashboard port may be reachable. Test spoofed `X-Forwarded-For` headers too.
5. Import a profile on mobile data. Verify handshake, DNS, app access, separate device profiles, and revocation. Confirm ordinary internet browsing does not go through DEN.
6. Add known files, users, photos, and Git commits, take a backup, and perform a staged restore. Then run **recover.sh on an empty replacement host** and verify actual databases, accounts, downloads, Git histories, certificates, and VPN keys.
7. Exercise a reviewed patch update and a sequential Nextcloud major upgrade. Test failed pulls, disconnected backup disk, and failed readiness without losing the pre-update snapshot. Recover the pre-update application state after a migration.
8. Reboot; verify Docker, DEN, WireGuard, VPN DNS, and both timers recover. Test a missed nightly job, failed backup alert, unhealthy container, and stale backup.
9. Verify the backup disk's absence never writes a repository under the underlying mountpoint. Inspect secret permissions and ensure logs do not disclose generated passwords.

10. On representative older hardware, test the target Wi-Fi adapter during installation and after a Fedora kernel update and reboot. Record its USB or PCI ID and driver. Confirm DEN services recover after network loss; an out-of-tree driver must have its own maintenance and Secure Boot signing plan.

11. With `FLUXER_ENABLED=yes`, confirm the setup token creates the first admin, new registration remains invite-only, `chat` returns 403 from outside without VPN, and voice works between LAN/VPN clients. Verify TCP 7881 and UDP 7882 are not forwarded at the router. Run `sudo den backup`, confirm a new full archive appears under `/srv/den/fluxer/backups`, then exercise `recover.sh` on a replacement host and verify users, messages, uploads, and attachments.

12. With `QBITTORRENT_ENABLED=yes`, confirm `downloads` has valid HTTPS, returns
403 outside without VPN, and requires an application login on LAN/VPN. Set a
permanent password; test an authorized torrent transfer and saved resume state
after a restart. Confirm UPnP/NAT-PMP remains off and no peer/direct UI ports are
published. Back up and restore settings, completed and partial downloads on a
replacement host. With the option absent or `no`, confirm no qBittorrent service
starts and no downloads route exists.

13. Exercise a monthly automatic maintenance window on a disposable Fedora
Server host: private Git authentication without prompts, sequential DEN releases
including a tested database migration, Fluxer upgrade when enabled, a stable
Fedora offline major upgrade, required reboot, and service recovery afterward.
Disconnect the backup disk, break source authentication, and fail a migration;
verify explicit alerts, no unsafe retry/downgrade, and recovery from the saved
snapshot. Confirm a masked update timer stays opted out across updates.

Keep a dated acceptance report for the hardware and release tested. These live checks have not yet been run for 0.1.0.