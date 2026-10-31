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
mkdir -p "$DEPLOY_DIR" "$DATA_DIR" "$BACKUP_MOUNT"
printf 'saved-secret\n' > "$DEPLOY_DIR/.env"
CALLS="$TEMP/calls"
STOPPED="$TEMP/stopped"
FAIL_BACKUP=false
FAIL_START=false
FAIL_PS=false
FAIL_STOP=false
ensure_backup_mount() { [[ -d "$BACKUP_MOUNT" ]]; }
compose() {
    printf 'compose %s\n' "$*" >> "$CALLS"
    case "$*" in
        'ps --status running --services') [[ "$FAIL_PS" == false ]] || return 1; printf 'nextcloud\nimmich-server\n' ;;
        'stop --timeout 120') [[ "$FAIL_STOP" == false ]] || return 1; touch "$STOPPED" ;;
        'ps --status running -q') [[ -f "$STOPPED" ]] ;;
        'start --wait --wait-timeout 900 nextcloud immich-server') [[ "$FAIL_START" == false ]] ;;
    esac
}
restic_cmd() {
    printf 'restic %s\n' "$*" >> "$CALLS"
    case "$1" in
        backup) [[ -f "$STOPPED" && "$FAIL_BACKUP" == false ]] ;;
        snapshots)
            if [[ "${2:-}" == --json ]]; then
                jq -n --arg path "$DATA_DIR" '[{hostname:"den",paths:[$path],tags:["den-v1"]}]'
            fi
            ;;
        restore) fail 'Unsafe restore reached Restic.' ;;
    esac
}
backup_stack
[[ -f "$DATA_DIR/system/deployment/.env" ]]
grep -Fq 'compose start --wait --wait-timeout 900 nextcloud immich-server' "$CALLS"
FAIL_BACKUP=true
: > "$CALLS"
if backup_stack; then fail 'Failed backup returned success.'; fi
grep -Fq 'compose start --wait --wait-timeout 900 nextcloud immich-server' "$CALLS"
FAIL_BACKUP=false; FAIL_START=true
if backup_stack; then fail 'Failed restart returned success.'; fi
FAIL_START=false; FAIL_PS=true
: > "$CALLS"
if backup_stack; then fail 'Failed Compose listing returned success.'; fi
if grep -Fq 'restic backup' "$CALLS"; then fail 'Snapshot taken without knowing service state.'; fi
FAIL_PS=false; FAIL_STOP=true
: > "$CALLS"
if backup_stack; then fail 'Failed Compose stop returned success.'; fi
if grep -Fq 'restic backup' "$CALLS"; then fail 'Snapshot taken while stop failed.'; fi
grep -Fq 'compose start --wait --wait-timeout 900 nextcloud immich-server' "$CALLS"
FAIL_STOP=false
for target in "$DATA_DIR" "$DATA_DIR/child" "$DEPLOY_DIR" "$BACKUP_MOUNT/new" / "$TEMP"; do
    if (restore_snapshot abcdef12 "$target") 2>/dev/null; then fail "Unsafe target accepted: $target"; fi
done
if (snapshot_details latest) 2>/dev/null; then fail 'Ambiguous snapshot accepted.'; fi
mv "$BACKUP_MOUNT" "$TEMP/unmounted"
: > "$CALLS"
if backup_stack; then fail 'Unmounted backup disk accepted.'; fi
[[ ! -s "$CALLS" ]] || fail 'Commands ran against an unmounted backup disk.'
printf 'Backup restart, failure propagation and restore-safety checks passed.\n'