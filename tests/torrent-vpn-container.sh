#!/usr/bin/env bash
# Explicit Docker integration check; never uses a real provider profile.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
command -v docker >/dev/null || fail 'Docker is required for this explicit integration check.'
TEMP="$(mktemp -d)"
NAME="den-vpn-check-$$"
NETWORK="$NAME-network"
VPN_IMAGE="$(sed -n 's/^    image: //p' "$ROOT/templates/compose.torrent-vpn.yml")"
QBIT_IMAGE="$(sed -n 's/^    image: \(lscr.io\/linuxserver\/qbittorrent:.*\)/\1/p' "$ROOT/templates/compose.yml")"
cleanup() {
    local result=$?
    trap - EXIT
    local container
    for container in "$NAME-probe" "$NAME"; do
        if docker container inspect "$container" >/dev/null 2>&1; then
            docker rm -f "$container" >/dev/null || result=1
        fi
    done
    if docker network inspect "$NETWORK" >/dev/null 2>&1; then
        docker network rm "$NETWORK" >/dev/null || result=1
    fi
    rm -rf "$TEMP"
    exit "$result"
}
trap cleanup EXIT
docker image inspect "$VPN_IMAGE" "$QBIT_IMAGE" >/dev/null ||
    fail 'Pull the pinned Gluetun and qBittorrent images before testing.'
python3 - "$TEMP/wg0.conf" <<'PY'
import base64
import os
from pathlib import Path
import sys
def key():
    return base64.b64encode(os.urandom(32)).decode()
Path(sys.argv[1]).write_text(f"""[Interface]
PrivateKey = {key()}
Address = 10.64.1.2/32

[Peer]
PublicKey = {key()}
Endpoint = 192.0.2.1:51820
AllowedIPs = 0.0.0.0/0
""")
PY
chmod 600 "$TEMP/wg0.conf"
install -m 644 "$ROOT/templates/torrent-resolv.conf" "$TEMP/resolv.conf"
docker network create "$NETWORK" >/dev/null
docker run --rm --network "$NETWORK" --cap-drop ALL \
    --entrypoint /usr/bin/curl "$QBIT_IMAGE" -fsS --connect-timeout 10 --max-time 20 \
    --output /dev/null http://1.1.1.1 ||
    fail 'Direct-network control failed; cannot meaningfully test the VPN kill switch.'
docker run -d --name "$NAME" --network "$NETWORK" --cap-add NET_ADMIN \
    --device /dev/net/tun:/dev/net/tun --sysctl net.ipv6.conf.all.disable_ipv6=1 \
    -e VPN_SERVICE_PROVIDER=custom -e VPN_TYPE=wireguard -e WIREGUARD_IMPLEMENTATION=userspace \
    -e FIREWALL=on -e FIREWALL_INPUT_PORTS=18427 -e DNS_ADDRESS=127.0.0.1 \
    -v "$TEMP/wg0.conf:/gluetun/wireguard/wg0.conf:ro,z" "$VPN_IMAGE" >/dev/null
ready=no
for attempt in {1..30}; do
    if docker exec "$NAME" iptables -S OUTPUT 2>/dev/null | grep -Fxq -- '-P OUTPUT DROP'; then
        ready=yes
        break
    fi
    sleep 1
done
[[ "$ready" == yes ]] || fail 'Gluetun did not install its fail-closed output firewall.'
docker run -d --name "$NAME-probe" --network "container:$NAME" --cap-drop ALL \
    --user 1000:1000 --security-opt no-new-privileges:true \
    -v "$TEMP/resolv.conf:/etc/resolv.conf:ro,z" \
    --entrypoint /bin/sh "$QBIT_IMAGE" -c 'while :; do sleep 3600; done' >/dev/null
docker exec "$NAME-probe" true
[[ "$(docker exec "$NAME-probe" cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == 1 ]] ||
    fail 'IPv6 is not disabled in the shared network namespace.'
[[ "$(docker exec "$NAME-probe" head -n 1 /etc/resolv.conf)" == 'nameserver 127.0.0.1' ]] ||
    fail 'Torrent DNS does not use sidecar loopback.'
assert_blocked() {
    local stage="$1" result=0
    docker exec "$NAME-probe" curl -sS --connect-timeout 2 --max-time 4 \
        --output /dev/null http://1.1.1.1 >"$TEMP/curl.log" 2>&1 || result=$?
    case "$result" in
        7|28) printf 'Protected egress blocked (%s).\n' "$stage" ;;
        *) fail "Expected refused/unreachable or timed-out egress ($stage), got curl exit $result." ;;
    esac
}
assert_blocked before-connection
docker stop --time 10 "$NAME" >/dev/null
assert_blocked sidecar-stopped
docker start "$NAME" >/dev/null
assert_blocked sidecar-restarted
printf 'Real Docker checks passed: direct control works; protected egress is blocked before connection, after sidecar stop and after restart; IPv6 disabled; loopback DNS configured.\n'
