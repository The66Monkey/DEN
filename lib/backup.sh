#!/usr/bin/env bash

ensure_backup_mount() {
    local data_filesystem="$DATA_DIR"
    [[ -d "$data_filesystem" ]] || data_filesystem="$(dirname "$DATA_DIR")"
    mountpoint -q "$BACKUP_MOUNT" || fail "Backup disk is not mounted: $BACKUP_MOUNT"
    [[ "$(stat -c %d "$BACKUP_MOUNT")" != "$(stat -c %d "$data_filesystem")" ]] || fail 'Backups must be on a separate filesystem.'
    [[ -w "$BACKUP_MOUNT" ]] || fail 'Backup disk is not writable.'
}

restic_cmd() {
    RESTIC_REPOSITORY="$BACKUP_MOUNT/den-restic" RESTIC_PASSWORD="$RESTIC_PASSWORD" restic "$@"
}

initialize_backup() {
    ensure_backup_mount
    if [[ -d "$BACKUP_MOUNT/den-restic" ]]; then
        restic_cmd snapshots >/dev/null
    else
        restic_cmd init
    fi
}

backup_stack() (
    set -euo pipefail
    ensure_backup_mount || exit 1
    fluxer_backup || exit 1
    restic_cmd snapshots >/dev/null || exit 1
    local -a running=()
    local result=0 stopped=false running_services active
    running_services="$(compose ps --status running --services)" || exit 1
    if [[ -n "$running_services" ]]; then
        mapfile -t running <<< "$running_services"
    fi
    cleanup_backup() {
        result=$?
        trap - EXIT INT TERM
        if [[ "$stopped" == true && ${#running[@]} -gt 0 ]]; then
            compose start --wait --wait-timeout 900 "${running[@]}" || result=1
        fi
        exit "$result"
    }
    trap cleanup_backup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir -p "$DATA_DIR/system/deployment" || exit 1
    cp -a "$DEPLOY_DIR/." "$DATA_DIR/system/deployment/" || exit 1
    stopped=true
    compose stop --timeout 120 || exit 1
    active="$(compose ps --status running -q)" || exit 1
    [[ -z "$active" ]] || fail 'Containers are still running; no snapshot was taken.'
    restic_cmd backup --host den --tag den-v1 --exclude "$DATA_DIR/cache" "$DATA_DIR"
)

snapshot_details() {
    local snapshot="$1"
    [[ "$snapshot" =~ ^[a-f0-9]{8,64}$ ]] || fail 'Use an explicit hexadecimal snapshot ID, not latest.'
    restic_cmd snapshots --json "$snapshot" | jq -e --arg path "$DATA_DIR" '
        if length == 1 and .[0].hostname == "den" and .[0].paths == [$path] and
            (.[0].tags | index("den-v1")) != null
        then .[0] else error("Not a unique DEN snapshot") end'
}

restore_snapshot() {
    local snapshot="$1" target="$2"
    ensure_backup_mount
    snapshot_details "$snapshot" >/dev/null
    [[ "$target" == /* ]] || fail 'Restore target must be absolute.'
    target="$(realpath -m "$target")"
    [[ "$target" != / ]] || fail 'Never restore over the filesystem root.'
    case "$target/" in
        /|"$DATA_DIR/"*|"$DEPLOY_DIR/"*|"$BACKUP_MOUNT/"*) fail 'Restore into a new staging directory, away from live data and backups.' ;;
    esac
    [[ ! -e "$target" ]] || fail 'Restore target already exists; DEN never overwrites it.'
    mkdir -p "$target"
    chmod 700 "$target"
    restic_cmd restore "$snapshot" --target "$target" --include "$DATA_DIR/**" --verify
    [[ -f "$target$DATA_DIR/system/deployment/.env" ]] || fail 'Restored deployment configuration is missing.'
    log "Verified restore is staged at $target$DATA_DIR; live services were not changed."
}

recovery_kit() {
    local destination="$1"
    [[ "$destination" == /* && -d "$destination" ]] || fail 'Choose an existing absolute directory on another device.'
    destination="$(realpath "$destination")"
    [[ "$(stat -c %d "$destination")" != "$(stat -c %d "$DATA_DIR")" ]] || fail 'Save the recovery kit on a separate filesystem.'
    [[ ! -e "$destination/den-recovery-kit" ]] || fail 'Recovery kit already exists; choose another directory.'
    install -d -m 700 "$destination/den-recovery-kit"
    cp -a "$DEPLOY_DIR/." "$destination/den-recovery-kit/"
    chmod 700 "$destination/den-recovery-kit"
    log 'Recovery kit saved. It contains passwords and VPN keys: keep it private, with an off-site copy.'
}