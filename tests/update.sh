#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/maintenance.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/live"
SOURCE_DIR="$TEMP/release"
CALLS="$TEMP/calls"
mkdir -p "$DEPLOY_DIR" "$SOURCE_DIR/templates" "$SOURCE_DIR/lib"
printf 'secret\n' > "$DEPLOY_DIR/.env"
printf '{}\n' > "$DEPLOY_DIR/routes.json"
printf 'nextcloud:33.0.10-apache\n' > "$DEPLOY_DIR/compose.yml"
printf 'nextcloud:33.0.11-apache\n' > "$SOURCE_DIR/templates/compose.yml"
printf '0.1.1\n' > "$SOURCE_DIR/VERSION"
printf 'write_routes() { printf "routes\\n" >> "$CALLS"; }\n' > "$SOURCE_DIR/lib/deploy.sh"
FAIL_PULL=false
FAIL_BACKUP=false
FAIL_START=false
mktemp() { command mktemp -d "$TEMP/candidate.XXXXXX"; }
copy_release() { mkdir -p "$2"; cp -a "$1/." "$2/"; }
compose() {
    printf 'compose %s\n' "$*" >> "$CALLS"
    case "$*" in
        'config --format json') jq -n --arg image "$(cat "$DEPLOY_DIR/compose.yml")" '{services:{nextcloud:{image:$image}}}' ;;
        pull) [[ "$FAIL_PULL" == false ]] ;;
    esac
}
backup_stack() { printf 'backup\n' >> "$CALLS"; [[ "$FAIL_BACKUP" == false ]]; }
start_stack() { printf 'start\n' >> "$CALLS"; [[ "$FAIL_START" == false ]]; }
install() { :; }
systemctl() { :; }
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
[[ -z "$(find "$TEMP" -maxdepth 1 -name 'candidate.*' -print -quit)" ]]
FAIL_START=true
if update_release "$SOURCE_DIR" >/dev/null; then fail 'Unhealthy update returned success.'; fi
printf 'nextcloud:35.0.0-apache\n' > "$SOURCE_DIR/templates/compose.yml"
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Skipped Nextcloud major accepted.'; fi
printf 'nextcloud:32.0.0-apache\n' > "$SOURCE_DIR/templates/compose.yml"
if (update_release "$SOURCE_DIR") >/dev/null 2>&1; then fail 'Nextcloud downgrade accepted.'; fi
printf 'Update pull/backup gates, saved secrets, readiness and major-version checks passed.\n'