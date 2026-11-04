#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/fluxer.sh"
source "$ROOT/lib/backup.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
DATA_DIR="$TEMP/data"
BACKUP_MOUNT="$TEMP/backup-disk"
mkdir -p "$DEPLOY_DIR" "$DATA_DIR/media" "$DATA_DIR/cache" "$BACKUP_MOUNT"
read_settings "$ROOT/config/example.env"
MEDIA_MOUNT=
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
BACKUP_MOUNT="$TEMP/backup-disk"
QBITTORRENT_ENABLED=yes
write_environment "$DEPLOY_DIR"
printf 'family media\n' > "$DATA_DIR/media/movie with spaces.txt"
printf 'regenerable cache\n' > "$DATA_DIR/cache/model"
mkdir -p "$DATA_DIR/media/.addon-work"
printf 'temporary add-on work\n' > "$DATA_DIR/media/.addon-work/temporary"
printf '%s/media/.addon-work\n' "$DATA_DIR" > "$DEPLOY_DIR/private/backup-excludes"
mkdir -p "$DATA_DIR/qbittorrent/qBittorrent" "$DATA_DIR/downloads/complete" "$DATA_DIR/downloads/incomplete"
printf 'saved torrent preferences and password hash\n' > "$DATA_DIR/qbittorrent/qBittorrent/qBittorrent.conf"
chmod 600 "$DATA_DIR/qbittorrent/qBittorrent/qBittorrent.conf"
printf 'authorized completed download\n' > "$DATA_DIR/downloads/complete/fixture"
printf 'partial download\n' > "$DATA_DIR/downloads/incomplete/fixture.part"
ensure_backup_mount() { [[ -d "$BACKUP_MOUNT" ]]; }
compose() {
    case "$*" in
        'ps --status running --services') printf 'nextcloud\n' ;;
        *) return 0 ;;
    esac
}
if [[ -n "${RESTIC_BIN:-}" ]]; then
    restic() { "$RESTIC_BIN" "$@"; }
fi
initialize_backup >/dev/null
(unset HOME XDG_CACHE_HOME; restic_cmd snapshots >/dev/null)
backup_stack >/dev/null
SNAPSHOT="$(restic_cmd snapshots --host den --tag den-v1 --json | jq -r 'last.id')"
restore_snapshot "$SNAPSHOT" "$TEMP/restored" >/dev/null
cmp "$DATA_DIR/media/movie with spaces.txt" "$TEMP/restored$DATA_DIR/media/movie with spaces.txt"
cmp "$DEPLOY_DIR/.env" "$TEMP/restored$DATA_DIR/system/deployment/.env"
[[ "$(stat -c %a "$TEMP/restored$DATA_DIR/system/deployment/.env")" == 600 ]]
grep -Fxq 'QBITTORRENT_ENABLED=yes' "$TEMP/restored$DATA_DIR/system/deployment/.env"
[[ ! -e "$TEMP/restored$DATA_DIR/cache/model" ]]
[[ ! -e "$TEMP/restored$DATA_DIR/media/.addon-work/temporary" ]]
for path in qbittorrent/qBittorrent/qBittorrent.conf downloads/complete/fixture downloads/incomplete/fixture.part; do
    cmp "$DATA_DIR/$path" "$TEMP/restored$DATA_DIR/$path"
done
[[ "$(stat -c %a "$TEMP/restored$DATA_DIR/qbittorrent/qBittorrent/qBittorrent.conf")" == 600 ]]
restic_cmd check --read-data >/dev/null
if (RESTIC_PASSWORD="$(openssl rand -hex 24)"; restic_cmd snapshots) >/dev/null 2>&1; then
    fail 'Repository opened with the wrong password.'
fi
printf 'Real encrypted Restic backup, verified restore and password checks passed.\n'