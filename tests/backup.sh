#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/fluxer.sh"
source "$ROOT/lib/backup.sh"
source "$ROOT/lib/maintenance.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
DATA_DIR="$TEMP/data"
BACKUP_MOUNT="$TEMP/backup-disk"
mkdir -p "$DEPLOY_DIR" "$DATA_DIR" "$BACKUP_MOUNT"
mkdir -p "$DEPLOY_DIR/private"
copy_release "$ROOT" "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/vaults/admin"
printf 'encrypted-vault-fixture\n' > "$DEPLOY_DIR/vaults/admin/credentials.kdbx"
chmod 600 "$DEPLOY_DIR/vaults/admin/credentials.kdbx"
printf 'saved-master-fixture\n' > "$DEPLOY_DIR/private/keepass-master-password"
printf 'services: {}\n' > "$DEPLOY_DIR/compose.yml"
printf 'saved-secret\n' > "$DEPLOY_DIR/.env"
CALLS="$TEMP/calls"
STOPPED="$TEMP/stopped"
FLUXER_ENABLED=yes
REXCTL_BIN="$TEMP/rexctl"
export CALLS
cat > "$REXCTL_BIN" <<'EOF'
#!/usr/bin/env bash
printf 'rexctl %s\n' "$*" >> "$CALLS"
EOF
chmod 700 "$REXCTL_BIN"
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
restore_deployment "$DATA_DIR/system/deployment" "$TEMP/recovered"
cmp "$DEPLOY_DIR/vaults/admin/credentials.kdbx" "$TEMP/recovered/vaults/admin/credentials.kdbx"
cmp "$DEPLOY_DIR/private/keepass-master-password" "$TEMP/recovered/private/keepass-master-password"
[[ "$(stat -c %a "$TEMP/recovered/vaults/admin/credentials.kdbx")" == 600 ]]
mv "$DATA_DIR/system/deployment/vaults" "$TEMP/saved-vaults"
restore_deployment "$DATA_DIR/system/deployment" "$TEMP/legacy-recovered"
[[ -d "$TEMP/legacy-recovered/private" && ! -e "$TEMP/legacy-recovered/vaults" ]]
grep -Fq 'compose start --wait --wait-timeout 900 nextcloud immich-server' "$CALLS"
fluxer_line="$(awk '/rexctl .* backup$/ {print NR; exit}' "$CALLS")"
restic_line="$(awk '/restic backup / {print NR; exit}' "$CALLS")"
[[ -n "$fluxer_line" && -n "$restic_line" && "$fluxer_line" -lt "$restic_line" ]] || fail 'Fluxer archive was not taken before the Restic snapshot.'
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
QBITTORRENT_VPN_ENABLED=yes
compose() {
    printf 'compose %s\n' "$*" >> "$CALLS"
    case "$*" in
        'ps --status running --services') printf 'nextcloud\ntorrent-vpn\nqbittorrent\n' ;;
        'stop --timeout 120') touch "$STOPPED" ;;
        'ps --status running -q') [[ -f "$STOPPED" ]] ;;
        'up -d --force-recreate --wait --wait-timeout 900 torrent-vpn qbittorrent') [[ "$FAIL_START" == false ]] ;;
    esac
}
: > "$CALLS"
backup_stack
grep -Fxq 'compose start --wait --wait-timeout 900 nextcloud' "$CALLS"
grep -Fxq 'compose up -d --force-recreate --wait --wait-timeout 900 torrent-vpn qbittorrent' "$CALLS"
FAIL_START=true
if backup_stack; then fail 'Failed VPN resume returned success.'; fi
FAIL_START=false
QBITTORRENT_VPN_ENABLED=no
for target in "$DATA_DIR" "$DATA_DIR/child" "$DEPLOY_DIR" "$BACKUP_MOUNT/new" / "$TEMP"; do
    if (restore_snapshot abcdef12 "$target") 2>/dev/null; then fail "Unsafe target accepted: $target"; fi
done
if (snapshot_details latest) 2>/dev/null; then fail 'Ambiguous snapshot accepted.'; fi
MEDIA_MOUNT="$TEMP/media-disk"
for target in "$MEDIA_MOUNT/den/media/new" "$MEDIA_MOUNT/den/downloads/new"; do
    : > "$CALLS"
    if (restore_snapshot abcdef12 "$target") 2>/dev/null; then fail "Live HDD restore target accepted: $target"; fi
    if grep -Fq 'restic restore' "$CALLS"; then fail 'Live HDD restore target reached Restic.'; fi
done
MEDIA_MOUNT=
mv "$BACKUP_MOUNT" "$TEMP/unmounted"
: > "$CALLS"
if backup_stack; then fail 'Unmounted backup disk accepted.'; fi
[[ ! -s "$CALLS" ]] || fail 'Commands ran against an unmounted backup disk.'
printf 'Backup restart, failure propagation and restore-safety checks passed.\n'