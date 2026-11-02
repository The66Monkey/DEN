# Keep DEN Running

## Weekly Glance

```bash
sudo den status
sudo den check
systemctl --failed
```

Hourly systemd checks watch container readiness, VPN/DNS, backup age, and data-disk capacity. Failures are written to the journal and `/etc/motd.d/den`; SSH login visibility depends on your system's MOTD configuration. There is no email, push notification, or external monitoring subscription. A stopped server cannot alert you about itself.

All DEN CLI operations share a nonblocking lock. A concurrent health check skips maintenance rather than incorrectly reporting stopped containers. Docker logs rotate with the local logging driver; `sudo den logs SERVICE` prints the most recent 100 lines. Logs can contain personal data: redact them before sharing.

## Automatic Monthly Maintenance (Default)

DEN enables `den-update.timer` on installation, recovery, and release updates.
It runs on the first of each month at 04:00 local time, plus up to 30 minutes of
random delay. A missed window runs when the timer next starts. The server may
be unavailable during backups, migrations, and reboots. No routine user action
is required when the update source and backup disk are available.

The job:

1. Waits for the shared maintenance lock, checks health, and takes a backup.
2. Fetches `UPDATE_REPOSITORY` (default: `https://github.com/The66Monkey/DEN.git`).
   Numeric `vMAJOR.MINOR.PATCH` tags on `main` are applied in increasing order,
   followed by a newer `main` release. Each tag must agree with its `VERSION`.
   Maintainers must bump `VERSION` to publish changes; the same release version
   is not silently replaced.
3. Validates and pulls each release, backs up before applying it, waits for app
   readiness, and keeps existing secrets. Nextcloud majors must be sequential.
   Database majors require the release's explicit migration scripts.
4. Updates enabled Fluxer through its backup-protected Rexctl upgrade.
5. Updates Fedora packages, checks health, and queries Fedora's official release
   metadata. If the next stable Server release exists, downloads and validates
   an offline upgrade to that single next version, takes another backup, and
   automatically reboots into the transaction. Beta/Rawhide and arbitrary
   skipped releases are not selected. Packages are not automatically erased to
   resolve dependency conflicts.
6. Otherwise reboots only if DNF reports a reboot requirement.

Failures stop the job and trigger `den-alert.service`, the journal, and MOTD.
An interrupted release leaves `/opt/den/private/update-in-progress`; subsequent
updates refuse to proceed until the failed update is investigated and recovered.
Never delete this marker merely to retry a partially migrated database.
There is no unsafe automatic database downgrade. DEN's application backup is
not a complete OS rollback image.

The private repository requires **one-time root Git authentication**, preferably
a read-only deploy key with a verified GitHub host key. Configure this before
installation; the installer checks access. Never embed a token/password in
`UPDATE_REPOSITORY`. Its code and migrations execute as root, so the repository
must remain trusted and protected. SSH keys/HTTPS credentials must be available
without prompts. Git authentication is not bundled into recovery kits; arrange
access on a replacement host. A failed fetch is an error, not an ignored update.

Inspect or run a window manually:

```bash
systemctl list-timers den-update.timer
journalctl -u den-update.service
sudo den auto-update
```

Change the schedule with a systemd override:

```bash
sudo systemctl edit den-update.timer
```

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-15 04:00:00
```

Then run `sudo systemctl daemon-reload` and
`sudo systemctl restart den-update.timer`. To opt out persistently, including
across release updates, use `sudo systemctl mask --now den-update.timer`.
Use `sudo systemctl unmask den-update.timer` and
`sudo systemctl enable --now den-update.timer` to restore the default.

Manual application remains available: `sudo bash update.sh` from a trusted
release checkout. Keep a private USB recovery kit with your server settings.
Use `sudo den verify-backup` if you suspect a backup problem, and
`sudo den prune` when you need to reclaim space; snapshots are not automatically
deleted. See [backup and recovery](backup.md).

### Major Database Migrations (Release Maintainers)

When a release changes a PostgreSQL major, include
`migrations/immich-db-OLD-NEW.sh` or
`migrations/nextcloud-db-OLD-NEW.sh`. DEN syntax-checks the script before changes,
pulls the target images, backs up, verifies containers are stopped, records the
in-progress marker, installs the candidate, and runs the migration with
`DEPLOY_DIR` and `DATA_DIR` exported. Then it starts and validates applications.

The migration must implement and test the actual database conversion (including
extensions and ownership) for that exact version pair. Never simply reuse old
PostgreSQL data with a new major. A release without its required script is
rejected before modifying live data. This provides unattended execution of
tested major migrations, not an invented universal conversion. Current image
pins remain the supported release combination; new app/database versions are
published together by DEN maintainers, not chosen independently at runtime.

When KeePass is enabled, after adding VPN devices run `sudo den keepass-sync` to add their profiles. The command adds missing generated entries and does not overwrite existing entries; record changed application credentials in KeePassXC yourself.

When Fluxer is enabled, `sudo den backup` includes a fresh full Rexctl archive before the encrypted Restic snapshot. Upgrades are explicit and use the same backup path:

```bash
sudo den fluxer-status
sudo den fluxer-upgrade
```

Monthly maintenance invokes the explicit Rexctl upgrade automatically when
Fluxer is enabled; Rexctl's separate auto-upgrader remains disabled. Fluxer
voice works on LAN/VPN only; do not forward TCP 7881 or UDP 7882 through the router.

Optional qBittorrent is managed by the normal DEN lifecycle and release update,
including cold backups and readiness checks. Inspect it with `sudo den logs
qbittorrent`. Monitor download and backup disk usage, keep UPnP/NAT-PMP disabled,
and use a permanent password. See [qBittorrent](qbittorrent.md) for storage and
the normal-connection privacy boundary.

## Stop Without Losing Data

```bash
sudo systemctl stop den-update.timer den-backup.timer den-check.timer den.service
sudo den stop
```

WireGuard remains up until explicitly stopped. To resume service management:

```bash
sudo systemctl start den.service den-backup.timer den-check.timer den-update.timer
```

Do not run `docker compose down -v`, prune Docker volumes blindly, delete `/srv/den`, or delete `.env` to repair passwords. DEN intentionally has no destructive uninstall command.