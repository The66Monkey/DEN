# Testing (Contributors)

For everyday checks, use `sudo den check`. This page is for changes to DEN,
not a setup checklist for household users.

## Validation Status

The first home-server release was deployed on a bare-metal Fedora Server host.
Verified during setup:

- All six enabled web apps reachable over trusted HTTPS on LAN.
- Real WireGuard handshake, VPN DNS, HTTPS and Cockpit access.
- Outside-source filtering, firewalld reload persistence and outbound connectivity.
- HDD media/download migration, persistent mount dependencies, read-only
  Jellyfin download access and writable metadata storage.
- Real encrypted backups and verified staged restores, including shared-HDD
  storage without backing up the repository itself.
- Automated Fedora test suite. An earlier deployment reboot passed before
  the latest firewall/storage changes.

Still to verify:

- Reboot with the final firewall and HDD mount configuration.
- Full recovery onto an empty replacement host.
- End-to-end live validation of the already enabled monthly update job,
  including a Fedora major upgrade and reboot. Scheduling and update commands
  are implemented; automated tests cover their ordering and failure paths.
- Owner confirmation of normal playback, photo upload, file sync and voice use.

These are follow-up checks, not claims of completed validation.
The optional shared-edge topology has since passed live acceptance: public
chat works on mobile data with VPN off, private home/AI access is denied there,
and existing business websites work through the independent edge. Migrated DNS
was checked over UDP/TCP, including legacy VPN forwarding and the VM's persistent
resolver. Real encrypted DEN and BASM backups completed without restarting DEN's
infrastructure containers. No post-migration host reboot, future ACME renewal,
cross-network voice/video or full replacement-host recovery is claimed.

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
Setup-review tests use a pseudo-terminal to check explicit acceptance,
restart/revalidation of edited settings, cancellation, end-of-input rejection,
terminal clearing and unchanged unattended behavior. Summaries are checked for
secret exclusion and public-service, torrent-VPN and shared-storage warnings.
Homepage checks cover the installed README, HTML escaping, LAN SSH instructions,
enabled-service links and private routing.
Infrastructure checks cover separate Compose ownership, embedded-edge exclusion,
private DNS/admin bindings, exact custom-route merging, conflicts/failure
preservation and bind-mounted route inode stability.
Independent AdGuard checks cover the private `dns.<domain>` HTTPS route,
edge-to-DNS network access and its VPN record, while installations without
independent infrastructure retain their existing routes and DNS records.
TV-subnet checks cover rejected overlaps, saved/legacy settings, Jellyfin-only
HTTPS allowlists, firewall-zone replacement, disabling and failure gates.
Isolated network tests exercise TV DNS/HTTPS access and denial of host
administration, voice ports and direct container/VPN addresses.

Real mount tests require user/mount namespaces. Real network tests also need
nftables, iproute2 and network namespaces; unavailable tests print a skip.
To run network checks as root, isolate them:

```bash
sudo unshare --mount --net bash tests/firewall-network.sh
```

Never run network-test setup directly in the host namespace.
CI/script tests do not prove app runtime, boot ordering or SELinux behavior.

### Torrent VPN

Unit checks cover the optional protected/direct modes, shared namespace,
private profile validation, missing-profile startup and failure gates, proxy
routing, explicit direct opt-out, and backup namespace recreation.

On a Docker host with the two pinned images already pulled, run:

```bash
sudo bash tests/torrent-vpn-container.sh
```

This creates and removes only its own temporary network/containers and synthetic
keys, never a provider profile or real torrents. It requires a working direct
HTTP control, then verifies blocked IPv4 egress before a VPN connection and
after sidecar stop/restart, IPv6 disablement and loopback DNS configuration.
It does **not** prove a working provider tunnel. Before relying on protection,
import a real profile, verify provider egress/peer IP, private Web UI access,
DNS through the tunnel, fail-closed behavior on tunnel loss, backup/restart and
host reboot. Do not publish profiles or raw provider logs.

### Optional AI

`tests/ai.sh` covers opt-in defaults, invalid configuration, stable private
admin/session secrets, local-only and dual-backend Compose rendering, private
hostname/homepage/VPN DNS.
Backup/update tests cover local Ollama quiescing, prior-state restoration,
provisioning order and failure gates. DDNS tests assert that AI does not add a
public record.

On a spare Fedora host, additionally verify first-admin creation with signups
disabled, real GPU generation and reported processor, model selection with the
workstation disconnected, trusted `ai.` HTTPS and LAN/VPN DNS, denial from
outside the allowlist. Test service
recreation and a host reboot separately; an enabled timer is not evidence that
a reboot was performed. Keep any existing lab database/secret out of disposable
test containers. Do not expose Ollama to test connectivity.

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
- Open `https://home.DOMAIN` on LAN/VPN; verify the README, SSH IP and service
  links. Confirm it remains private when public chat is enabled.
- Test playback, photo upload, file sync and HTTPS Git clone/push.
- Test mobile VPN handshake/DNS and blocked private apps without VPN.
  With Fluxer enabled, test public chat login, invites, WebSockets and calls
  between external networks with VPN off. Confirm other app routes return 403.
  With Fluxer disabled, public HTTPS/voice must be blocked by the guard.
- Reload firewalld; confirm LAN/VPN, outbound access and outside denial.
- Back up and verify a staged restore; recover to an empty host and check
  actual accounts, files, databases and VPN keys.
- Reboot; verify guard and storage precede Docker and all services return.
  Boot without the HDD: DEN must not write bulk data onto the SSD.
- Check optional Fluxer public voice discovery after update/restore and WAN IP
  changes, LAN hairpin calls, qBittorrent resume/seeding,
  read-only Jellyfin downloads and KeePass export.
- Test shared-HDD backup/restore without including the repository itself.
- Exercise updates, required database migrations, monthly Fedora upgrade/reboot,
  failed downloads, missing disks and interrupted maintenance.
  Confirm errors stop unsafe retries and masked update timers stay disabled.

Record which hardware/release was tested. Do not treat passing unit tests as
a completed live release test.
