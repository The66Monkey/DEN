#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
read_settings "$ROOT/config/example.env"
write_environment "$TEMP/deployment"
[[ "$(stat -c %a "$TEMP/deployment/.env")" == 600 ]]
[[ "$(stat -c %a "$TEMP/deployment")" == 700 ]]
read_settings "$TEMP/deployment/.env"
[[ ${#DB_PASSWORD} == 48 && ${#RESTIC_PASSWORD} == 48 ]]
if (write_environment "$TEMP/deployment") 2>/dev/null; then exit 1; fi
for invalid in 'LAN_IP=192.168.1.999' 'LAN_IP=192.168.2.10' 'LAN_IP=192.168.1.0' 'LAN_CIDR=0.0.0.0/8' 'LAN_CIDR=192.168.1.1/24' 'DOMAIN=$(touch /tmp/den-injection)' 'BACKUP_MOUNT=/srv/den'; do
    if (printf -v "${invalid%%=*}" '%s' "${invalid#*=}"; validate_settings) 2>/dev/null; then
        fail "Accepted invalid setting: $invalid"
    fi
done
for subnet in '10.44.0.0/24' '172.30.44.0/24'; do
    if (LAN_CIDR="$subnet"; LAN_IP="${subnet%0/*}10"; validate_settings) 2>/dev/null; then exit 1; fi
done
printf 'DOMAIN=home.example.net\nDOMAIN=other.example.net\n' > "$TEMP/duplicate.env"
if (read_settings "$TEMP/duplicate.env") 2>/dev/null; then exit 1; fi
printf 'UNKNOWN=value\n' > "$TEMP/unknown.env"
if (read_settings "$TEMP/unknown.env") 2>/dev/null; then exit 1; fi
printf 'Config and secret-generation checks passed.\n'