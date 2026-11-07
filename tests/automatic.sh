#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/automatic.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/live"
CALLS="$TEMP/calls"
mkdir -p "$DEPLOY_DIR/lib/hosts" "$DEPLOY_DIR/private"
printf '0.1.0\n' > "$DEPLOY_DIR/VERSION"
printf 'test\n' > "$DEPLOY_DIR/.env"
for library in core deploy maintenance fluxer backup; do
    : > "$DEPLOY_DIR/lib/$library.sh"
done
: > "$DEPLOY_DIR/lib/hosts/fedora.sh"
UPDATE_REPOSITORY=https://github.com/The66Monkey/DEN.git
FAIL_BACKUP=false
FAIL_RELEASE=false
FAIL_DNF=false
REBOOT_STATUS=0
OS_UPGRADE=false
FLUXER_ENABLED=no
health_check() { printf 'health\n' >> "$CALLS"; }
backup_stack() { printf 'backup\n' >> "$CALLS"; [[ "$FAIL_BACKUP" == false ]]; }
read_settings() { :; }
fluxer_upgrade() { printf 'fluxer\n' >> "$CALLS"; }
mktemp() { command mktemp -d "$TEMP/stage.XXXXXX"; }
automatic_releases() { printf 'releases\n' >> "$CALLS"; [[ "$FAIL_RELEASE" == false ]]; }
fedora_version_id() { printf '43\n'; }
curl() {
    local current next version
    current="$(fedora_version_id)"
    next=$((current + 1))
    if [[ "$OS_UPGRADE" == true ]]; then version="$next"; else version="$next Beta"; fi
    jq -n --arg version "$version" '[{version:$version, arch:"x86_64", variant:"Server"}]' > "${@: -1}"
}
dnf() {
    printf 'dnf %s\n' "$*" >> "$CALLS"
    if [[ "$*" == 'needs-restarting --reboothint' ]]; then return "$REBOOT_STATUS"; fi
    [[ "$FAIL_DNF" == false ]]
}
systemctl() { printf 'systemctl %s\n' "$*" >> "$CALLS"; }

FAIL_BACKUP=true
if automatic_update >/dev/null; then fail 'Automatic update ignored backup failure.'; fi
[[ "$(cat "$CALLS")" == $'health\nbackup' ]]
FAIL_BACKUP=false
FAIL_RELEASE=true
: > "$CALLS"
if automatic_update >/dev/null; then fail 'Automatic update ignored release failure.'; fi
if grep -q '^dnf -y --refresh upgrade$' "$CALLS"; then fail 'Host upgraded after release failure.'; fi
FAIL_RELEASE=false
: > "$CALLS"
automatic_update >/dev/null
if grep -q '^systemctl reboot$' "$CALLS"; then fail 'Unneeded reboot.'; fi
if grep -q 'system-upgrade download' "$CALLS"; then fail 'Fedora beta was selected.'; fi
REBOOT_STATUS=1
: > "$CALLS"
automatic_update >/dev/null
grep -Fxq 'systemctl reboot' "$CALLS"
REBOOT_STATUS=2
if (automatic_update) >/dev/null 2>&1; then fail 'Reboot check error returned success.'; fi
REBOOT_STATUS=0
FAIL_DNF=true
: > "$CALLS"
if automatic_update >/dev/null; then fail 'Failed host upgrade returned success.'; fi
if grep -q '^systemctl reboot$' "$CALLS"; then fail 'Rebooted after failed host upgrade.'; fi
FAIL_DNF=false
OS_UPGRADE=false
: > "$CALLS"
automatic_update >/dev/null
! grep -q 'system-upgrade download' "$CALLS"
OS_UPGRADE=true
FLUXER_ENABLED=yes
: > "$CALLS"
automatic_update >/dev/null
grep -Fxq fluxer "$CALLS"
grep -Fxq 'dnf -y system-upgrade download --releasever 44' "$CALLS"
grep -Fxq 'dnf -y offline reboot' "$CALLS"
[[ "$(grep -c '^backup$' "$CALLS")" == 2 ]]
if grep -q -- '--allowerasing' "$CALLS"; then fail 'Automatic upgrade may erase required packages.'; fi
dnf() {
    printf 'dnf %s\n' "$*" >> "$CALLS"
    [[ "$*" != *'system-upgrade download'* ]]
}
: > "$CALLS"
if automatic_update >/dev/null; then fail 'Failed major-upgrade download returned success.'; fi
! grep -q 'offline reboot' "$CALLS"
curl() { printf 'invalid JSON\n' > "${@: -1}"; }
: > "$CALLS"
if automatic_update >/dev/null 2>&1; then fail 'Invalid release metadata returned success.'; fi
! grep -q 'system-upgrade download' "$CALLS"
touch "$DEPLOY_DIR/private/update-in-progress"
if (automatic_update) >/dev/null 2>&1; then fail 'Automatic retry of interrupted release.'; fi
rm "$DEPLOY_DIR/private/update-in-progress"

source "$ROOT/lib/automatic.sh"
git() {
    local last="${!#}"
    case "$*" in
        'clone --quiet --branch main '*)
            mkdir -p "$last"
            printf '0.3.0\n' > "$last/VERSION"
            ;;
        *' tag --merged origin/main --sort=version:refname')
            printf 'v0.1.0\nv0.2.0\nv0.3.0\n'
            ;;
        *' checkout --quiet --detach '*)
            case "${@: -1}" in
                v*) printf '%s\n' "$last" | sed 's/^v//' > "$2/VERSION" ;;
                origin/main) printf '0.3.0\n' > "$2/VERSION" ;;
            esac
            ;;
        *) fail "Unexpected Git call: $*" ;;
    esac
}
update_release() {
    printf 'release %s\n' "$(cat "$1/VERSION")" >> "$CALLS"
    cp "$1/VERSION" "$DEPLOY_DIR/VERSION"
}
: > "$CALLS"
automatic_releases
[[ "$(cat "$CALLS")" == $'release 0.2.0\nrelease 0.3.0' ]]
grep -Fxq 'OnCalendar=*-*-01 04:00:00' "$ROOT/templates/systemd/den-update.timer"
grep -Fxq 'Persistent=true' "$ROOT/templates/systemd/den-update.timer"
grep -Fxq 'OnFailure=den-alert.service' "$ROOT/templates/systemd/den-update.service"
printf 'Monthly update backup gates, sequential releases, Fedora selection, errors and reboot checks passed.\n'
