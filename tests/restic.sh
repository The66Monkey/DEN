#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/backup.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
DATA_DIR="$TEMP/data"
BACKUP_MOUNT="$TEMP/backup-disk"
mkdir -p "$DEPLOY_DIR" "$DATA_DIR/media" "$DATA_DIR/cache" "$BACKUP_MOUNT"
read_settings "$ROOT/config/example.env"
BACKUP_MOUNT="$TEMP/backup-disk"
write_environment "$DEPLOY_DIR"
printf 'family media\n' > "$DATA_DIR/media/movie with spaces.txt"
printf 'regenerable cache\n' > "$DATA_DIR/cache/model"
ensure_backup_mount() { [[ -d "$BACKUP_MOUNT" ]]; }
compose() {
    case "$*" in
        'ps --status running --services') printf 'nextcloud\n' ;;
        *) return 0 ;;
    esac
}
if [[ -n "${RESTIC_BIN:-}" ]]; then
    restic_cmd() {
        RESTIC_REPOSITORY="$BACKUP_MOUNT/den-restic" RESTIC_PASSWORD="$RESTIC_PASSWORD" "$RESTIC_BIN" "$@"
    }
fi
initialize_backup >/dev/null
backup_stack >/dev/null
SNAPSHOT="$(restic_cmd snapshots --host den --tag den-v1 --json | jq -r 'last.id')"
restore_snapshot "$SNAPSHOT" "$TEMP/restored" >/dev/null
cmp "$DATA_DIR/media/movie with spaces.txt" "$TEMP/restored$DATA_DIR/media/movie with spaces.txt"
cmp "$DEPLOY_DIR/.env" "$TEMP/restored$DATA_DIR/system/deployment/.env"
[[ "$(stat -c %a "$TEMP/restored$DATA_DIR/system/deployment/.env")" == 600 ]]
[[ ! -e "$TEMP/restored$DATA_DIR/cache/model" ]]
restic_cmd check --read-data >/dev/null
if (RESTIC_PASSWORD="$(openssl rand -hex 24)"; restic_cmd snapshots) >/dev/null 2>&1; then
    fail 'Repository opened with the wrong password.'
fi
printf 'Real encrypted Restic backup, verified restore and password checks passed.\n'