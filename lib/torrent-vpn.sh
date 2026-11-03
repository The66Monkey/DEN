#!/usr/bin/env bash

torrent_vpn_profile_ready() {
    [[ -s "$DEPLOY_DIR/private/torrent-vpn/wg0.conf" && ! -L "$DEPLOY_DIR/private/torrent-vpn/wg0.conf" ]]
}

torrent_vpn_setting() {
    local value="$1" temporary
    temporary="$(mktemp "$DEPLOY_DIR/private/torrent-vpn-setting.XXXXXX")" || return 1
    if ! awk -v value="$value" '
        /^QBITTORRENT_VPN_ENABLED=/ {next}
        {print}
        END {print "QBITTORRENT_VPN_ENABLED=" value}
    ' "$DEPLOY_DIR/.env" > "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    chmod 600 "$temporary"
    mv "$temporary" "$DEPLOY_DIR/.env" || return 1
    QBITTORRENT_VPN_ENABLED="$value"
}

torrent_vpn() {
    local source="$1" temporary directory="$DEPLOY_DIR/private/torrent-vpn"
    [[ "${QBITTORRENT_ENABLED:-no}" == yes ]] || fail 'Enable qBittorrent before configuring its VPN.'
    [[ ! -L "$DEPLOY_DIR/private" && ! -L "$directory" ]] || fail 'Private VPN storage cannot be a symlink.'
    install -d -m 700 "$directory" || return 1
    case "$source" in
        wait)
            ! torrent_vpn_profile_ready || fail 'A provider profile is already installed. Use den stop, or import its replacement; wait is for initial setup only.'
            compose stop --timeout 120 qbittorrent || return 1
            torrent_vpn_setting yes || return 1
            compose stop --timeout 120 torrent-vpn || return 1
            write_routes || return 1
            log 'Torrent VPN is required. qBittorrent is stopped; import a provider profile with den torrent-vpn /path/to/provider.conf.'
            ;;
        off)
            log 'Explicit direct mode: trackers and peers will see your normal public IP.'
            compose stop --timeout 120 qbittorrent || return 1
            if [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes ]]; then
                compose stop --timeout 120 torrent-vpn || return 1
            fi
            torrent_vpn_setting no || return 1
            compose up -d --no-deps --force-recreate --wait --wait-timeout 180 qbittorrent || return 1
            write_routes || return 1
            log 'qBittorrent is running without an outbound VPN.'
            ;;
        *)
            [[ "$source" == /* ]] || fail 'Use an absolute profile path, or explicitly choose wait/off.'
            temporary="$(mktemp "$directory/import.XXXXXX")" || return 1
            if ! python3 "$DEPLOY_DIR/templates/import-torrent-wireguard.py" "$source" "$LAN_CIDR" > "$temporary"; then
                rm -f "$temporary"
                return 1
            fi
            if ! compose stop --timeout 120 qbittorrent; then
                rm -f "$temporary"
                return 1
            fi
            if ! torrent_vpn_setting yes; then
                rm -f "$temporary"
                return 1
            fi
            if [[ -f "$directory/wg0.conf" ]]; then
                install -m 600 "$directory/wg0.conf" "$directory/previous.conf" || return 1
            fi
            chmod 600 "$temporary"
            mv "$temporary" "$directory/wg0.conf" || return 1
            compose up -d --force-recreate --wait --wait-timeout 180 torrent-vpn qbittorrent || {
                log 'Torrent VPN did not become ready. No direct fallback was enabled; check den logs torrent-vpn.'
                return 1
            }
            write_routes || return 1
            log "Provider profile installed privately. Open https://downloads.$DOMAIN; DNS and torrent traffic use the outbound tunnel."
            log 'IPv6 is blocked; profile DNS is replaced by the VPN sidecar resolver. Take a new encrypted backup.'
            ;;
    esac
}
