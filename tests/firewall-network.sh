#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(readlink /proc/self/ns/net)" != "$(readlink /proc/1/ns/net)" ]] || {
    printf 'Run firewall tests in an isolated network namespace, never on the host.\n' >&2
    exit 1
}
[[ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]] || exit 1
source "$ROOT/lib/core.sh"
source "$ROOT/lib/hosts/fedora.sh"
mount --make-rprivate /
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
read_settings "$ROOT/config/example.env"
LAN_IP=192.168.50.58
LAN_CIDR=192.168.50.0/24
ACME_CHALLENGE=dns-desec
FLUXER_ENABLED=yes
write_network_guard > "$TEMP/dns.nft"
ACME_CHALLENGE=http
write_network_guard > "$TEMP/http.nft"
mkdir -p /run/netns
mount -t tmpfs tmpfs /run/netns
python3 "$ROOT/tests/firewall-network.py" "$TEMP/dns.nft" "$TEMP/http.nft"
