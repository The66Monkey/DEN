# Verification

## Automated Checks

On a development machine with Bash, jq, OpenSSL, ShellCheck, Restic, and Docker Compose v2:

```bash
bash tests/run.sh
```

Tests need neither root nor a Docker daemon. `COMPOSE_BIN` and `RESTIC_BIN` optionally point to standalone validators. All fixtures live in temporary directories. The suite checks:

- Strict config, missing/unknown/duplicate keys, malformed/private IP ranges, overlapping subnets, and non-evaluated input.
- Unique generated secrets, root-only environment permissions, and refusal to regenerate an existing environment.
- Exactly eleven Compose services, only LAN-bound proxy ports, bind-mounted storage, digest-pinned images, readiness probes, and all private HTTPS routes.
- Cold backup ordering, saved deployment config, restarting previously running services, and failure propagation for Docker listing/stopping, Restic, restart, and missing backup disk.
- Explicit snapshot selection and rejection of existing, live-root, backup-root, and filesystem-root restore destinations.
- A real encrypted Restic repository, media and configuration restore with verification, cache exclusions, password rejection, and full repository-data checking.
- Per-device VPN addresses and keys, protected profiles, duplicate/name rejection, and persistent peer revocation (with mocked WireGuard).
- Update refusal after failed downloads/backups, preserved environment secrets, failed readiness reporting, staging cleanup, and Nextcloud major-version gates (with mocked Compose).

CI runs these same non-root tests. They validate the scripts and file-level backup contract, **not** the application containers' runtime behavior.

## Required Live Acceptance

Before marking a DEN release production-ready, use a fresh Debian 13 VM or dedicated PC and a separate backup disk. Set up a real domain and router as documented. Use non-sensitive fixtures.

1. Time from running the installer to healthy applications. Record download speed, hardware, and first-user setup time; the under-one-hour goal is not validated by the unit tests.
2. Confirm each pinned image starts on the minimum CPU class, Nextcloud creates its account/database, Immich reaches its matched database and ML worker, and Forgejo admin creation works.
3. Open all four apps from a LAN client with valid public certificates. Check upload/download, movie playback, a photo thumbnail/search, Nextcloud desktop sync, and HTTPS Git clone/push.
4. Check TCP 80/443 bindings and UDP 51820. Scan from outside: application HTTPS must be 403 without VPN, and no database, SSH Git, DNS, or dashboard port may be reachable. Test spoofed `X-Forwarded-For` headers too.
5. Import a profile on mobile data. Verify handshake, DNS, app access, separate device profiles, and revocation. Confirm ordinary internet browsing does not go through DEN.
6. Add known files, users, photos, and Git commits, take a backup, and perform a staged restore. Then run **recover.sh on an empty replacement host** and verify actual databases, accounts, downloads, Git histories, certificates, and VPN keys.
7. Exercise a reviewed patch update and a sequential Nextcloud major upgrade. Test failed pulls, disconnected backup disk, and failed readiness without losing the pre-update snapshot. Recover the pre-update application state after a migration.
8. Reboot; verify Docker, DEN, WireGuard, VPN DNS, and both timers recover. Test a missed nightly job, failed backup alert, unhealthy container, and stale backup.
9. Verify the backup disk's absence never writes a repository under the underlying mountpoint. Inspect secret permissions and ensure logs do not disclose generated passwords.

Keep a dated acceptance report for the hardware and release tested. These live checks have not yet been run for 0.1.0.