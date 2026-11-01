# Keep DEN Running

## Weekly Glance

```bash
sudo den status
sudo den check
systemctl --failed
```

Hourly systemd checks watch container readiness, VPN/DNS, backup age, and data-disk capacity. Failures are written to the journal and `/etc/motd.d/den`; SSH login visibility depends on your system's MOTD configuration. There is no email, push notification, or external monitoring subscription. A stopped server cannot alert you about itself.

All DEN CLI operations share a nonblocking lock. A concurrent health check skips maintenance rather than incorrectly reporting stopped containers. Docker logs rotate with the local logging driver; `sudo den logs SERVICE` prints the most recent 100 lines. Logs can contain personal data: redact them before sharing.

## Monthly Maintenance

1. Read DEN's release notes and the upstream applications' upgrade requirements. Use a separate trusted checkout containing the next approved release, not arbitrary edited Compose images.
2. Apply it from that checkout:

```bash
sudo bash update.sh
```

The updater validates Compose, enforces sequential Nextcloud major upgrades, downloads the candidate images while the old stack is running, takes a cold pre-update backup, applies the release, and waits for readiness. Failed downloads or backups prevent deployment changes. Failed readiness is reported and does not trigger an unsafe image-only downgrade. Follow [recovery](backup.md) instead.

3. Test playback, uploads, file sync, Git, and VPN. Save a new external recovery kit. Database-major changes, Immich's matched database requirements, and application migration notes must be reviewed by DEN maintainers; the CLI is not a universal migration engine.
4. Update Fedora packages during a maintenance window:

```bash
sudo dnf upgrade --refresh
```

Reboot when required, then run `sudo den check`. DEN does not enable automatic container updates or unattended host reboots. Fedora releases have a short support window; plan a Fedora release upgrade at least yearly, before the installed release reaches end of life. Follow Fedora's current official upgrade procedure, take and verify an external DEN backup first, then check Docker, WireGuard, DNS, timers, and applications after the upgrade. DEN does not automate OS release upgrades; pinned application images do not update themselves.

5. Run `sudo den verify-backup` and, after checking retention implications, `sudo den prune`. A staged restore drill every month is recommended.

When KeePass is enabled, after adding VPN devices run `sudo den keepass-sync` to add their profiles. The command adds missing generated entries and does not overwrite existing entries; record changed application credentials in KeePassXC yourself.

When Fluxer is enabled, `sudo den backup` includes a fresh full Rexctl archive before the encrypted Restic snapshot. Upgrades are explicit and use the same backup path:

```bash
sudo den fluxer-status
sudo den fluxer-upgrade
```

DEN does not enable Rexctl auto-upgrades. Fluxer voice works on LAN/VPN only by default; do not forward TCP 7881 or UDP 7882 through the router.

## Stop Without Losing Data

```bash
sudo systemctl stop den-backup.timer den-check.timer den.service
sudo den stop
```

WireGuard remains up until explicitly stopped. To resume service management:

```bash
sudo systemctl start den.service den-backup.timer den-check.timer
```

Do not run `docker compose down -v`, prune Docker volumes blindly, delete `/srv/den`, or delete `.env` to repair passwords. DEN intentionally has no destructive uninstall command.