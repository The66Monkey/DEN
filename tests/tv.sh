#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/hosts/fedora.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
mkdir -p "$DEPLOY_DIR/private/infrastructure" "$DEPLOY_DIR/templates"
cp "$ROOT/templates/merge-routes.jq" "$DEPLOY_DIR/templates/"
read_settings "$ROOT/config/example.env"
[[ -z "$TV_CIDR" ]]
write_routes
cp "$DEPLOY_DIR/routes.json" "$TEMP/default.json"
TV_CIDR=192.168.60.0/24
validate_settings
if (write_routes) >"$TEMP/error" 2>&1; then fail 'Enabled TV subnet without AdGuard infrastructure.'; fi
if (write_network_guard) >"$TEMP/error" 2>&1; then fail 'Enabled TV firewall without AdGuard infrastructure.'; fi
cmp "$TEMP/default.json" "$DEPLOY_DIR/routes.json"
grep -Fq 'requires independent AdGuard infrastructure' "$TEMP/error"
touch "$DEPLOY_DIR/private/external-edge" "$DEPLOY_DIR/private/infrastructure/compose.yml"
FLUXER_ENABLED=yes
QBITTORRENT_ENABLED=yes
write_routes
jq -e '
    .http.middlewares.private.ipAllowList.sourceRange == ["192.168.1.0/24", "10.44.0.0/24"] and
    .http.middlewares["media-private"].ipAllowList.sourceRange == ["192.168.1.0/24", "10.44.0.0/24", "192.168.60.0/24"] and
    .http.routers.media.middlewares == ["media-private", "headers"] and
    .http.routers.chat.middlewares == ["headers"] and
    all(.http.routers | to_entries[] | select(.key != "media" and .key != "chat");
        .value.middlewares[0] == "private") and
    .http.services.media.loadBalancer.servers == [{"url":"http://jellyfin:8096"}]
' "$DEPLOY_DIR/routes.json" >/dev/null
write_network_guard > "$TEMP/tv.nft"
grep -Fq 'ip saddr 192.168.60.0/24 goto tv' "$TEMP/tv.nft"
grep -Fq 'ip daddr 192.168.1.10 tcp dport { 53, 443 } return' "$TEMP/tv.nft"
grep -Fq 'ip daddr 192.168.1.10 udp dport 53 return' "$TEMP/tv.nft"

for invalid in 192.168.60.1/24 192.168.1.0/24 192.168.0.0/16 10.44.0.128/25 \
    172.30.44.0/24 172.30.45.0/24 172.16.0.0/12 203.0.113.0/24 192.168.60.0/31 \
    192.168.60.0/032 192.168.060.0/24 invalid '192.168.60.0/24;echo'; do
    if (TV_CIDR="$invalid"; validate_settings) >"$TEMP/error" 2>&1; then
        fail "Accepted invalid TV subnet: $invalid"
    fi
    [[ -s "$TEMP/error" ]]
done
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/saved"
read_settings "$TEMP/saved/.env"
[[ "$TV_CIDR" == 192.168.60.0/24 ]]
read_settings "$ROOT/config/example.env"
[[ -z "$TV_CIDR" ]]

CALLS="$TEMP/firewall-calls"
firewall-cmd() {
    printf '%s\n' "$*" >> "$CALLS"
    case "$*" in
        '--permanent --get-zones') printf 'public den-vpn den-tv\n' ;;
        '--permanent --zone=den-tv --list-sources') printf '192.168.61.0/24\n' ;;
    esac
}
TV_CIDR=192.168.60.0/24
configure_tv_zone
grep -Fq -- '--zone=den-tv --set-target=DROP' "$CALLS"
grep -Fq -- '--zone=den-tv --remove-source=192.168.61.0/24' "$CALLS"
grep -Fq -- '--zone=den-tv --add-source=192.168.60.0/24' "$CALLS"
configure_network_guard() { printf 'guard\n' >> "$CALLS"; }
tv_setup
grep -Fxq 'guard' "$CALLS"
grep -Fxq -- '--reload' "$CALLS"
: > "$CALLS"
TV_CIDR=
tv_setup
! grep -Fq -- '--add-source=' "$CALLS"
jq -e '.http.middlewares["media-private"] == null and .http.routers.media.middlewares == ["private", "headers"]' "$DEPLOY_DIR/routes.json" >/dev/null
FLUXER_ENABLED=no
QBITTORRENT_ENABLED=no
rm "$DEPLOY_DIR/private/external-edge" "$DEPLOY_DIR/private/infrastructure/compose.yml"
write_routes
cmp "$TEMP/default.json" "$DEPLOY_DIR/routes.json"
(
    configure_network_guard() { return 1; }
    write_routes() { fail 'Firewall failure reached route update.'; }
    if (tv_setup) >"$TEMP/error" 2>&1; then fail 'TV setup ignored firewall failure.'; fi
    grep -Fq 'Could not apply TV network guard' "$TEMP/error"
)
printf 'TV subnet validation, persistence, private routes, restricted firewall and disable/failure checks passed.\n'
