# Testing (Contributors)

For everyday checks, use `sudo den check`. This page is for changes to DEN,
not a setup checklist for household users.

## Automated Checks

Dependencies: Bash, jq, OpenSSL, ShellCheck, Restic, Python 3 with pykeepass,
and Docker Compose v2.

```bash
bash tests/run.sh
```

No root or Docker daemon is needed. `COMPOSE_BIN` and `RESTIC_BIN` can select
standalone validators. Fixtures use temporary directories.

Coverage includes config/secrets, Compose routes, optional features, storage
mounts, encrypted backup/restore, VPN profiles, firewall rules, update gates
and monthly maintenance failure paths.

Real mount tests require user/mount namespaces. Real network tests also need
nftables, iproute2 and network namespaces; unavailable tests print a skip.
To run network checks as root, isolate them:

```bash
sudo unshare --mount --net bash tests/firewall-network.sh
```

Never run network-test setup directly in the host namespace.
CI/script tests do not prove app runtime, boot ordering or SELinux behavior.

## One-Command Local Test Stack

On a Podman-capable Fedora machine:

```bash
bin/den-local up [--with-qbittorrent]
bin/den-local test
bin/den-local creds
bin/den-local down
```

This is HTTP-only test data, without certificates, VPN or scheduled backups.
`down` preserves data. `reset --yes` deletes the local test's data and settings.
Override detected IP/storage with `DEN_LOCAL_IP` and `DEN_LOCAL_STORAGE`.

## Release Checks on Fedora Server

Use a spare host or VM and non-sensitive data:

- Install; verify all enabled apps, valid HTTPS and first-user setup.
- Test playback, photo upload, file sync and HTTPS Git clone/push.
- Test mobile VPN handshake/DNS and blocked outside access without VPN.
  With DNS-01 coexistence, leave the other server's web forwards unchanged.
- Reload firewalld; confirm LAN/VPN, outbound access and outside denial.
- Back up and verify a staged restore; recover to an empty host and check
  actual accounts, files, databases and VPN keys.
- Reboot; verify guard and storage precede Docker and all services return.
  Boot without the HDD: DEN must not write bulk data onto the SSD.
- Check optional Fluxer chat/voice and recovery, qBittorrent resume/seeding,
  read-only Jellyfin downloads and KeePass export.
- Test shared-HDD backup/restore without including the repository itself.
- Exercise updates, required database migrations, monthly Fedora upgrade/reboot,
  failed downloads, missing disks and interrupted maintenance.
  Confirm errors stop unsafe retries and masked update timers stay disabled.

Record which hardware/release was tested. Do not treat passing unit tests as
a completed live release test.
