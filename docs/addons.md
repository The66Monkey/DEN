# Separate add-on integration

Core DEN supplies photos, files, media, Git and private networking. AI and ebook
narration are maintained in the separate
[DEN+ repository](https://git.scandinavianhacking.dedyn.io/The66Monkey/DEN-plus), not enabled through
core configuration. This interface is generic; no add-on is installed by default.

## Administrator-controlled files

An installed add-on can create these files under `/opt/den/private`:

- `addon-hook`: regular administrator-owned shell file, not writable by group
  or others. DEN invokes it with one action argument using Bash. It must reject
  unknown actions and report errors through a nonzero exit status.
- `compose-addon.yml`: Compose override, combined after core and
  `compose-custom.yml`. Add-ons must validate the complete composition.
- `routes-addon.json`: additive Traefik HTTP routes merged after
  `routes-custom.json`; duplicate managed/custom names fail explicitly.
- `dns-addon.conf`: dnsmasq fragment appended after `dns-custom.conf`. Add-ons
  must validate the full generated configuration before restarting DNS.
- `backup-excludes`: optional Restic exclude-file, maintained by the
  administrator/add-on. Never exclude irreplaceable data accidentally.

All files are trusted local deployment configuration, not user-uploaded input.
The private folder survives updates and is included in deployment backups.
An add-on must refuse to overwrite files owned by another extension.

## Lifecycle

DEN calls `prepare` before starting containers, `start` after containers become
healthy, `stop` before stopping containers, and `check` during health checks.
`prepare` must be idempotent and restore native runtimes/services when necessary
after recovery. The hook runs while DEN holds its operation lock: **never call
`sudo den` recursively from a hook**, or it will deadlock/fail.

Backups call `before-backup` before copying deployment configuration and stopping
containers, then `after-backup` on cleanup, including a failed pause/snapshot.
The add-on must durably record prior process/timer state before pausing and
restore exactly that state, not start everything indiscriminately. Stop trigger
timers before workers so they cannot restart during the snapshot.

DEN's backup includes `/srv/den`; keep add-on data, deployment, configuration,
stable secrets and recovery entry point there. Ephemeral runtime binaries can
remain in `/opt`, provided `prepare` restores them. No cloud backup/inference
is introduced by these hooks.

Updates retain overlays during candidate Compose validation and refuse a
candidate lacking installed hook support. Add-on software is versioned and
updated separately; updating DEN never updates an add-on's code.

## Migrating an older enhanced DEN

Earlier versions accepted `AI_*`, `AUDIOBOOKS_*`, `NVIDIA_POWER_LIMIT_W` and
`NVIDIA_GPU_ID` in `/opt/den/.env`. These settings no longer belong to core DEN.
The parser refuses them with migration guidance rather than silently disabling
working services. Back up and follow DEN+'s migration guide **before** replacing
the live core deployment. Preserve existing WebUI data/secrets, native model
weights, ebook/audio files and GPU power limits. Standalone labs need explicit
migration rather than automatic adoption.

The repository split itself makes no live-server changes. DEN+'s source is public
on local Forgejo by choice; do not publish deployment secrets or SSH keys.
