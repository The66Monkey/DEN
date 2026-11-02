#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/maintenance.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/live"
DATA_DIR="$TEMP/data"
SOURCE_DIR="$TEMP/release"
CALLS="$TEMP/calls"
mkdir -p "$DEPLOY_DIR/private" "$SOURCE_DIR/templates" "$SOURCE_DIR/lib/hosts"
printf 'secret\n' > "$DEPLOY_DIR/.env"
printf '{}\n' > "$DEPLOY_DIR/routes.json"
printf 'nextcloud:33.0.10-apache\n' > "$DEPLOY_DIR/compose.yml"
printf 'nextcloud:33.0.11-apache\n' > "$SOURCE_DIR/templates/compose.yml"
printf '0.1.1\n' > "$SOURCE_DIR/VERSION"
printf 'write_routes() { printf "routes\\n" >> "$CALLS"; }\n' > "$SOURCE_DIR/lib/deploy.sh"
printf 'configure_fedora_host() { printf "firewall\\n" >> "$CALLS"; }\n' > "$SOURCE_DIR/lib/hosts/fedora.sh"
FAIL_PULL=false
FAIL_BACKUP=false
FAIL_START=false
LIVE_DB_MAJOR=17
SOURCE_DB_MAJOR=17
mktemp() { command mktemp -d "$TEMP/candidate.XXXXXX"; }
copy_release() { mkdir -p "$2"; cp -a "$1/." "$2/"; }
compose() {
    printf 'compose %s\n' "$*" >> "$CALLS"
    case "$*" in
        'config --format json')
            database="$SOURCE_DB_MAJOR"
            [[ "$DEPLOY_DIR" != "$TEMP/live" ]] || database="$LIVE_DB_MAJOR"
            jq -n --arg image "$(cat "$DEPLOY_DIR/compose.yml")" --arg db "$database" \
                '{services:{nextcloud:{image:$image}, "immich-db":{image:"postgres:14"}, "nextcloud-db":{image:("postgres:"+$db)}}}'
            ;;
        pull) [[ "$FAIL_PULL" == false ]] ;;
    esac
}
backup_stack() { printf 'backup\n' >> "$CALLS"; [[ "$FAIL_BACKUP" == false ]]; }
start_stack() { printf 'start\n' >> "$CALLS"; [[ "$FAIL_START" == false ]]; }
prepare_storage() { printf 'storage\n' >> "$CALLS"; }
install() { :; }
TIMER_STATE=disabled
systemctl() {
    printf 'systemctl %s\n' "$*" >> "$CALLS"
    if [[ "$*" == 'is-enabled den-update.timer' ]]; then printf '%s\n' "$TIMER_STATE"; fi
}
FAIL_PULL=true
if update_release "$SOURCE_DIR" >/dev/null; then fail 'Failed pull returned success.'; fi
if grep -Fxq backup "$CALLS"; then fail 'Backup ran after a failed pull.'; fi
grep -Fq '33.0.10' "$DEPLOY_DIR/compose.yml"
FAIL_PULL=false; FAIL_BACKUP=true
: > "$CALLS"
if update_release "$SOURCE_DIR" >/dev/null; then fail 'Failed backup returned success.'; fi
if grep -Fxq start "$CALLS"; then fail 'New stack started after a failed backup.'; fi
grep -Fq '33.0.10' "$DEPLOY_DIR/compose.yml"
FAIL_BACKUP=false
: > "$CALLS"
update_release "$SOURCE_DIR" >/dev/null
grep -Fq '33.0.11' "$DEPLOY_DIR/compose.yml"
cmp "$DEPLOY_DIR/.env" <(printf 'secret\n')
grep -Fxq backup "$CALLS"
grep -Fxq start "$CALLS"
grep -Fxq firewall "$CALLS"
[[ "$(grep -n '^backup$' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^firewall$' "$CALLS" | cut -d: -f1)" ]]
[[ "$(grep -n '^firewall$' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^start$' "$CALLS" | cut -d: -f1)" ]]
[[ -z "$(find "$TEMP" -maxdepth 1 -name 'candidate.*' -print -quit)" ]]
QBITTORRENT_ENABLED=yes
: > "$CALLS"
update_release "$SOURCE_DIR" >/dev/null
grep -Fxq storage "$CALLS"
[[ "$(grep -n '^backup$' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^storage$' "$CALLS" | cut -d: -f1)" ]]
[[ "$(grep -n '^storage$' "$CALLS" | cut -d: -f1)" -lt "$(grep -n '^start$' "$CALLS" | cut -d: -f1)" ]]
QBITTORRENT_ENABLED=no
FAIL_START=true
if update_release "$SOURCE_DIR" >/dev/null; then fail 'Unhealthy update returned success.'; fi
[[ -f "$DEPLOY_DIR/private/update-in-progress" ]]
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Interrupted update was retried.'; fi
rm "$DEPLOY_DIR/private/update-in-progress"
FAIL_START=false
printf 'nextcloud:35.0.0-apache\n' > "$SOURCE_DIR/templates/compose.yml"
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Skipped Nextcloud major accepted.'; fi
printf 'nextcloud:32.0.0-apache\n' > "$SOURCE_DIR/templates/compose.yml"
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Nextcloud downgrade accepted.'; fi
printf 'nextcloud:33.0.11-apache\n' > "$SOURCE_DIR/templates/compose.yml"
SOURCE_DB_MAJOR=18
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Database major change without migration accepted.'; fi
mkdir -p "$SOURCE_DIR/migrations" "$DATA_DIR"
cat > "$SOURCE_DIR/migrations/nextcloud-db-17-18.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'verified migration fixture\n' > "$DATA_DIR/migrated"
[[ "${FAIL_MIGRATION:-no}" != yes ]]
EOF
: > "$CALLS"
update_release "$SOURCE_DIR" >/dev/null
grep -Fxq 'compose stop --timeout 120' "$CALLS"
grep -Fxq 'compose ps --status running -q' "$CALLS"
grep -Fxq 'verified migration fixture' "$DATA_DIR/migrated"
[[ ! -e "$DEPLOY_DIR/private/update-in-progress" ]]
rm "$DATA_DIR/migrated"
: > "$CALLS"
if FAIL_MIGRATION=yes update_release "$SOURCE_DIR" >/dev/null; then fail 'Failed database migration returned success.'; fi
[[ -e "$DEPLOY_DIR/private/update-in-progress" ]]
if grep -Fxq start "$CALLS"; then fail 'Apps started after a failed database migration.'; fi
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Failed database migration was retried.'; fi
rm "$DEPLOY_DIR/private/update-in-progress"
LIVE_DB_MAJOR=18
SOURCE_DB_MAJOR=17
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Database downgrade accepted.'; fi
SOURCE_DB_MAJOR=18
TIMER_STATE=masked
: > "$CALLS"
update_release "$SOURCE_DIR" >/dev/null
if grep -Fxq 'systemctl enable --now den-update.timer' "$CALLS"; then fail 'Masked update timer was re-enabled.'; fi
printf 'Update pull/backup gates, saved secrets, readiness and major-version checks passed.\n'