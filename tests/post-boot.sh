#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1090
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
CALLS="$TEMP/calls"
STATE=active
FAIL_CHECK=no
FAIL_HTTPS=no
HTTPS_STATUS=200
DOMAIN=home.example.net
LAN_IP=192.168.1.10
systemctl() {
    printf 'systemctl %s\n' "$*" >> "$CALLS"
    if [[ "$1" == show ]]; then printf '%s\n' "$STATE"; fi
    if [[ "$1" == is-enabled ]]; then printf 'enabled\n'; fi
}
nvidia-smi() { return 0; }
curl() { printf 'https %s\n' "$*" >> "$CALLS"; printf '%s' "$HTTPS_STATUS"; [[ "$FAIL_HTTPS" == no ]]; }
/usr/local/bin/den() { printf 'health\n' >> "$CALLS"; [[ "$FAIL_CHECK" == no ]]; }
sleep() { printf 'sleep %s\n' "$*" >> "$CALLS"; }
install() { :; }
cat() { printf 'fixture-boot\n'; }
date() { printf 'fixture-time\n'; }
# Exercise the function with an isolated success receipt, without live settings.
source <(sed -n '/^verify_boot()/,/^}$/p' "$ROOT/templates/post-boot-check.sh" |
    sed "s|/srv/den/cache/boot-verified|$TEMP/verified|")
verify_boot >/dev/null
[[ -f "$TEMP/verified" ]]
! grep -q 'systemctl start' "$CALLS"
grep -Fq -- '--resolve home.home.example.net:443:192.168.1.10' "$CALLS"
STATE=failed
: > "$CALLS"
verify_boot >/dev/null
grep -Fxq 'systemctl start den.service' "$CALLS"
STATE=active
FAIL_CHECK=yes
: > "$CALLS"
if verify_boot >/dev/null 2>&1; then exit 1; fi
[[ "$(grep -c '^health$' "$CALLS")" == 3 ]]
[[ "$(grep -c '^sleep 30$' "$CALLS")" == 2 ]]
! grep -q 'systemctl start' "$CALLS"
FAIL_CHECK=no
FAIL_HTTPS=yes
: > "$CALLS"
if verify_boot >/dev/null 2>&1; then exit 1; fi
[[ "$(grep -c '^https ' "$CALLS")" == 3 ]]
FAIL_HTTPS=no
HTTPS_STATUS=302
if verify_boot >/dev/null 2>&1; then exit 1; fi
STATE=inactive
: > "$CALLS"
if verify_boot >/dev/null 2>&1; then exit 1; fi
! grep -q 'systemctl start' "$CALLS"
printf 'Post-boot recovery, strict HTTPS, bounded retries and non-restart checks passed.\n'
