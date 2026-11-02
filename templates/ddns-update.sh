#!/usr/bin/env bash
set -euo pipefail
umask 077

STATE_FILE="${1:?Usage: ddns-update.sh <state-file>}"
: "${DOMAIN:?DOMAIN is required}"
: "${DESEC_TOKEN:?DESEC_TOKEN is required}"
: "${FLUXER_ENABLED:=no}"
: "${QBITTORRENT_ENABLED:=no}"

valid_ipv4() {
    local octet
    local -a octets
    [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$1"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

if ! current_ip="$(curl -4 -fsS --max-time 20 https://api.ipify.org)"; then
    printf 'DEN DDNS: could not determine the public IPv4 address.\n' >&2
    exit 1
fi
if ! valid_ipv4 "$current_ip"; then
    printf 'DEN DDNS: public IPv4 lookup returned an invalid address.\n' >&2
    exit 1
fi

last_ip=''
if [[ -f "$STATE_FILE" ]]; then
    last_ip="$(<"$STATE_FILE")"
fi
if [[ "$current_ip" == "$last_ip" ]]; then
    printf 'DEN DDNS: public IPv4 is unchanged (%s).\n' "$current_ip"
    exit 0
fi

hostnames="home.$DOMAIN,media.$DOMAIN,photos.$DOMAIN,files.$DOMAIN,git.$DOMAIN"
if [[ "$FLUXER_ENABLED" == yes ]]; then
    hostnames+=",chat.$DOMAIN"
fi
if [[ "$QBITTORRENT_ENABLED" == yes ]]; then
    hostnames+=",downloads.$DOMAIN"
fi
printf 'DEN DDNS: updating %s to %s.\n' "$hostnames" "$current_ip"
if ! printf 'header = "Authorization: Token %s"\n' "$DESEC_TOKEN" |
    curl -4 -fsS --max-time 30 -K - -o /dev/null \
        "https://update.dedyn.io/?hostname=$hostnames&myipv4=$current_ip&myipv6=preserve"; then
    printf 'DEN DDNS: deSEC update failed; the timer will retry.\n' >&2
    exit 1
fi

printf '%s\n' "$current_ip" > "$STATE_FILE.tmp"
mv -f "$STATE_FILE.tmp" "$STATE_FILE"
printf 'DEN DDNS: deSEC records updated.\n'
