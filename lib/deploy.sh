#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/torrent-vpn.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ai.sh"

compose() {
    local -a profiles=()
    local -a files=(-f "$DEPLOY_DIR/compose.yml")
    case "${1:-}" in up|start|run) ensure_media_storage ;; esac
    if [[ "${QBITTORRENT_ENABLED:-no}" == yes ]]; then
        profiles=(--profile torrents)
        files+=(-f "$DEPLOY_DIR/templates/compose.torrents.yml")
        if [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes ]]; then
            files+=(-f "$DEPLOY_DIR/templates/compose.torrent-vpn.yml")
        fi
    fi
    if [[ "${ACME_CHALLENGE:-http}" == dns-desec ]]; then
        files+=(-f "$DEPLOY_DIR/templates/compose.dns.yml")
    fi
    if [[ "${AI_ENABLED:-no}" == yes ]]; then
        files+=(-f "$DEPLOY_DIR/templates/compose.ai.yml")
    fi
    if [[ -f "$DEPLOY_DIR/private/external-edge" ]]; then
        files+=(-f "$DEPLOY_DIR/templates/compose.external-edge.yml")
    fi
    env -i PATH="$PATH" HOME="${HOME:-/root}" docker compose \
        --project-name den --project-directory "$DEPLOY_DIR" \
        --env-file "$DEPLOY_DIR/.env" "${files[@]}" "${profiles[@]}" "$@"
}

check_media_disk() {
    [[ -n "${MEDIA_MOUNT:-}" ]] || return 0
    [[ "$(realpath -e "$MEDIA_MOUNT")" == "$MEDIA_MOUNT" ]] || fail 'MEDIA_MOUNT cannot contain symlinks.'
    mountpoint -q "$MEDIA_MOUNT" || fail "Mount the secondary storage disk first: $MEDIA_MOUNT"
    [[ -w "$MEDIA_MOUNT" ]] || fail 'Secondary storage disk is not writable.'
    case "$(findmnt -n -o FSTYPE --mountpoint "$MEDIA_MOUNT")" in
        ext4|xfs|btrfs) ;;
        *) fail 'Secondary storage needs a local ext4, XFS, or Btrfs filesystem with Linux ownership and SELinux support.' ;;
    esac
    [[ "$(stat -c %d "$MEDIA_MOUNT")" != "$(stat -c %d /srv)" ]] || fail 'Secondary storage must be a different filesystem from the OS data root.'
    if [[ "$(stat -c %d "$MEDIA_MOUNT")" == "$(stat -c %d "$BACKUP_MOUNT")" ]]; then
        [[ "${ALLOW_SHARED_MEDIA_BACKUP:-no}" == yes ]] || fail 'Secondary storage and backups must be on different filesystems unless ALLOW_SHARED_MEDIA_BACKUP=yes.'
        log 'WARNING: media/downloads and backups share a filesystem; disk failure loses both.'
    fi
}

ensure_media_storage() {
    [[ -n "${MEDIA_MOUNT:-}" ]] || return 0
    check_media_disk
    local directory
    for directory in media downloads; do
        mountpoint -q "$DATA_DIR/$directory" || fail "Secondary storage bind mount is missing: $DATA_DIR/$directory"
        [[ "$(realpath -e "$MEDIA_MOUNT/den/$directory")" == "$MEDIA_MOUNT/den/$directory" ]] || fail 'Secondary storage folders cannot contain symlinks.'
        [[ "$DATA_DIR/$directory" -ef "$MEDIA_MOUNT/den/$directory" ]] || fail "Wrong secondary storage bind mount: $DATA_DIR/$directory"
    done
}

media_mount_unit() {
    local directory="$1" disk_unit
    disk_unit="$(systemd-escape --path --suffix=mount "$MEDIA_MOUNT")"
    cat <<EOF
[Unit]
Description=DEN secondary $directory storage
RequiresMountsFor=$MEDIA_MOUNT/den/$directory
BindsTo=$disk_unit
After=$disk_unit

[Mount]
What=$MEDIA_MOUNT/den/$directory
Where=$DATA_DIR/$directory
Type=none
Options=bind

[Install]
WantedBy=multi-user.target
EOF
}

configure_media_storage() {
    [[ -n "${MEDIA_MOUNT:-}" ]] || return 0
    check_media_disk
    local directory unit units=
    for directory in media downloads; do
        [[ ! -L "$DATA_DIR" && ! -L "$DATA_DIR/$directory" ]] || fail 'DEN storage paths cannot be symlinks.'
        mkdir -p "$MEDIA_MOUNT/den/$directory" "$DATA_DIR/$directory"
        [[ "$(realpath -e "$MEDIA_MOUNT/den/$directory")" == "$MEDIA_MOUNT/den/$directory" ]] || fail 'Secondary storage folders cannot contain symlinks.'
        [[ -z "$(find "$DATA_DIR/$directory" -mindepth 1 -print -quit)" ]] || fail 'Existing media/downloads require an explicit migration; DEN will not hide them with a mount.'
        unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
        [[ ! -e "/etc/systemd/system/$unit" ]] || fail "Storage mount unit already exists: $unit"
        units+=" $unit"
    done
    for directory in media downloads; do
        unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
        media_mount_unit "$directory" > "/etc/systemd/system/$unit"
        chmod 644 "/etc/systemd/system/$unit"
    done
    install -d -m 755 /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/den-storage.conf <<EOF
[Unit]
RequiresMountsFor=$DATA_DIR/media $DATA_DIR/downloads
BindsTo=$units
After=$units
EOF
    chmod 644 /etc/systemd/system/docker.service.d/den-storage.conf
    systemctl daemon-reload
    for directory in media downloads; do
        unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
        systemctl enable --now "$unit"
    done
    ensure_media_storage
}

write_homepage() {
    local dns_admin=no
    if [[ -f "$DEPLOY_DIR/private/external-edge" && -f "$DEPLOY_DIR/private/infrastructure/compose.yml" ]]; then dns_admin=yes; fi
    install -d -m 755 "$DEPLOY_DIR/home" || return 1
    install -m 644 "$DEPLOY_DIR/docs/images/mascot.png" "$DEPLOY_DIR/home/mascot.png" || return 1
    jq -nr --arg domain "$DOMAIN" --arg ip "$LAN_IP" \
        --arg fluxer "${FLUXER_ENABLED:-no}" --arg torrents "${QBITTORRENT_ENABLED:-no}" --arg ai "${AI_ENABLED:-no}" --arg dns_admin "$dns_admin" \
        --rawfile template "$DEPLOY_DIR/templates/home.html" '
        ([
            {name: "media", label: "Media - Jellyfin"},
            {name: "photos", label: "Photos - Immich"},
            {name: "files", label: "Files - Nextcloud"},
            {name: "git", label: "Git - Forgejo"}
        ] + (if $fluxer == "yes" then [{name: "chat", label: "Chat - Fluxer (public, invite-only)"}] else [] end)
          + (if $torrents == "yes" then [{name: "downloads", label: "Downloads - qBittorrent"}] else [] end)
          + (if $ai == "yes" then [{name: "ai", label: "AI - Open WebUI"}] else [] end)
          + (if $dns_admin == "yes" then [{name: "dns", label: "DNS - AdGuard Home"}] else [] end)
        | map("<li><a href=\"https://" + (.name + "." + $domain | @html) + "/\">" + (.label | @html) + "</a></li>")
        | join("\n")) as $services |
        reduce [
            ["{{DOMAIN}}", ($domain | @html)],
            ["{{LAN_IP}}", ($ip | @html)],
            ["{{SERVICES}}", $services]
        ][] as $replacement ($template; split($replacement[0]) | join($replacement[1]))
    ' > "$DEPLOY_DIR/home/index.html" || return 1
    chmod 644 "$DEPLOY_DIR/home/index.html"
}

write_routes() {
    local torrent_host=qbittorrent candidate merged dns_admin=no
    require_tv_infrastructure
    candidate="$(mktemp)" || return 1
    merged="$(mktemp)" || { rm -f "$candidate"; return 1; }
    if [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes ]]; then torrent_host=torrent-vpn; fi
    if [[ -f "$DEPLOY_DIR/private/external-edge" && -f "$DEPLOY_DIR/private/infrastructure/compose.yml" ]]; then dns_admin=yes; fi
    jq -n --arg domain "$DOMAIN" --arg ip "$LAN_IP" --arg lan "$LAN_CIDR" --arg tv "${TV_CIDR:-}" --arg fluxer "${FLUXER_ENABLED:-no}" --arg torrents "${QBITTORRENT_ENABLED:-no}" --arg ai "${AI_ENABLED:-no}" --arg dns_admin "$dns_admin" --arg ai_url "http://172.30.44.1:28413" --arg qbit "http://$torrent_host:$QBITTORRENT_WEBUI_PORT" --arg chat "http://172.30.44.1:$FLUXER_PROXY_PORT" '
        {http: {
            middlewares: {
                private: {ipAllowList: {sourceRange: [$lan, "10.44.0.0/24"]}},
                headers: {headers: {contentTypeNosniff: true, referrerPolicy: "same-origin"}},
                dav: {redirectRegex: {
                    regex: "https://(.*)/.well-known/(?:card|cal)dav",
                    replacement: "https://${1}/remote.php/dav/", permanent: true}}
            } + (if $tv != "" then {
                "media-private": {ipAllowList: {sourceRange: [$lan, "10.44.0.0/24", $tv]}}
            } else {} end),
            routers: (reduce (["home", "media", "photos", "files", "git"] + (if $fluxer == "yes" then ["chat"] else [] end) + (if $torrents == "yes" then ["downloads"] else [] end) + (if $ai == "yes" then ["ai"] else [] end) + (if $dns_admin == "yes" then ["dns"] else [] end))[] as $name ({};
                .[$name] = {rule: ("Host(`" + (if $name == "chat" then "chat." else $name + "." end) + $domain + "`)") ,
                    entryPoints: ["websecure"], service: $name,
                    middlewares: ((if $name == "chat" then ["headers"] elif $name == "media" and $tv != "" then ["media-private", "headers"] else ["private", "headers"] end) + (if $name == "files" then ["dav"] else [] end)),
                    tls: {certResolver: "home"}}) + {
                "home-lan-ip": {
                    rule: ("Host(`" + $ip + "`)"), entryPoints: ["websecure"],
                    service: "home", middlewares: ["private", "headers"], tls: {}
                }}),
            services: ({
                home: {loadBalancer: {servers: [{url: "http://homepage:80"}]}},
                media: {loadBalancer: {servers: [{url: "http://jellyfin:8096"}]}},
                photos: {loadBalancer: {servers: [{url: "http://immich-server:2283"}]}},
                files: {loadBalancer: {servers: [{url: "http://nextcloud:80"}]}},
                git: {loadBalancer: {servers: [{url: "http://forgejo:3000"}]}}
            } + (if $fluxer == "yes" then {chat: {loadBalancer: {servers: [{url: $chat}]}}} else {} end)
              + (if $torrents == "yes" then {downloads: {loadBalancer: {servers: [{url: $qbit}]}}} else {} end))
              + (if $ai == "yes" then {ai: {loadBalancer: {servers: [{url: $ai_url}]}}} else {} end)
              + (if $dns_admin == "yes" then {dns: {loadBalancer: {servers: [{url: "http://dns:3000"}]}}} else {} end)
        }}' > "$candidate" || { rm -f "$candidate" "$merged"; return 1; }
    if [[ -f "$DEPLOY_DIR/private/routes-custom.json" ]]; then
        if ! jq -s -e -f "$DEPLOY_DIR/templates/merge-routes.jq" \
            "$candidate" "$DEPLOY_DIR/private/routes-custom.json" > "$merged"; then
            rm -f "$candidate" "$merged"
            return 1
        fi
    else
        cp "$candidate" "$merged" || { rm -f "$candidate" "$merged"; return 1; }
    fi
    cat "$merged" > "$DEPLOY_DIR/routes.json" || { rm -f "$candidate" "$merged"; return 1; }
    rm -f "$candidate" "$merged"
}

infrastructure_compose() {
    env -i PATH="$PATH" HOME="${HOME:-/root}" docker compose \
        --project-name den-infrastructure \
        --project-directory "$DEPLOY_DIR/private/infrastructure" \
        --env-file "$DEPLOY_DIR/private/infrastructure/.env" \
        -f "$DEPLOY_DIR/private/infrastructure/compose.yml" "$@"
}

prepare_storage() {
    local directory
    ensure_media_storage
    [[ ! -L "$DATA_DIR" && ! -L "$DEPLOY_DIR" ]] || fail 'DEN roots cannot be symlinks.'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"
    for directory in traefik jellyfin media/movies media/tv media/music cache/jellyfin cache/immich immich/library immich/database nextcloud/html nextcloud/database forgejo system; do
        mkdir -p "$DATA_DIR/$directory"
    done
    chmod 700 "$DATA_DIR/system" "$DATA_DIR/traefik"
    chown 1000:1000 "$DATA_DIR/jellyfin" "$DATA_DIR/cache/jellyfin" "$DATA_DIR/media" "$DATA_DIR/media/"* "$DATA_DIR/forgejo"
    if [[ "${QBITTORRENT_ENABLED:-no}" == yes ]]; then
        mkdir -p "$DATA_DIR/qbittorrent" "$DATA_DIR/downloads/incomplete" "$DATA_DIR/downloads/complete"
        prepare_qbittorrent_config "$DATA_DIR/qbittorrent" "downloads.$DOMAIN"
        chown 1000:1000 "$DATA_DIR/qbittorrent" "$DATA_DIR/qbittorrent/qBittorrent" \
            "$DATA_DIR/qbittorrent/qBittorrent/qBittorrent.conf" \
            "$DATA_DIR/downloads" "$DATA_DIR/downloads/incomplete" "$DATA_DIR/downloads/complete"
    fi
    [[ -f "$DATA_DIR/traefik/acme.json" ]] || install -m 600 /dev/null "$DATA_DIR/traefik/acme.json"
}

prepare_qbittorrent_config() {
    local directory="$1" domains="$2"
    [[ ! -L "$directory" ]] || fail 'qBittorrent configuration directory cannot be a symlink.'
    mkdir -p "$directory/qBittorrent"
    [[ ! -L "$directory/qBittorrent" && ! -L "$directory/qBittorrent/qBittorrent.conf" ]] || fail 'qBittorrent configuration cannot be a symlink.'
    [[ ! -e "$directory/qBittorrent/qBittorrent.conf" ]] || return 0
    (
        umask 077
        cat > "$directory/qBittorrent/qBittorrent.conf" <<EOF
[LegalNotice]
Accepted=true

[BitTorrent]
Session\\DefaultSavePath=/downloads/complete/
Session\\TempPath=/downloads/incomplete/
Session\\TempPathEnabled=true
Session\\Port=$QBITTORRENT_PEER_PORT
Session\\UseUPnP=false

[Preferences]
Connection\\UPnP=false
Downloads\\SavePath=/downloads/complete/
Downloads\\TempPath=/downloads/incomplete/
Downloads\\TempPathEnabled=true
WebUI\\Address=*
WebUI\\Port=$QBITTORRENT_WEBUI_PORT
WebUI\\ServerDomains=$domains
WebUI\\HostHeaderValidation=true
WebUI\\CSRFProtection=true
WebUI\\LocalHostAuth=true
WebUI\\AuthSubnetWhitelistEnabled=false
EOF
    )
}

check_host() {
    [[ "$EUID" == 0 ]] || fail 'Run installation with sudo.'
    local ID flag memory
    source /etc/os-release
    [[ "$ID" == fedora ]] || fail 'DEN currently targets Fedora Server only.'
    [[ "$(uname -m)" == x86_64 ]] || fail 'DEN currently tests x86_64 PCs only.'
    for flag in cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3; do
        grep -qm1 -w "$flag" /proc/cpuinfo || fail "CPU lacks $flag; Immich needs x86-64-v2 (usually 2012 or newer)."
    done
    memory="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    (( memory >= 7500000 )) || fail 'At least 8 GB RAM is required; 16 GB is recommended.'
    if [[ "$FLUXER_ENABLED" == yes && "$memory" -lt 15000000 ]]; then
        log 'Fluxer is enabled on a host with under 16 GB RAM; expect resource pressure with Immich.'
    fi
    ip -4 -o address show | grep -Fq " $LAN_IP/" || fail 'LAN_IP is not assigned to this server.'
    [[ ! -e /etc/wireguard/wg0.conf && ! -e /etc/systemd/system/den.service ]] || fail 'Existing wg0 or DEN installation found.'
    if ss -H -ltn '( sport = :80 or sport = :443 )' | grep -q .; then fail 'TCP 80/443 is already in use.'; fi
    if ss -H -lun "( sport = :$WIREGUARD_PORT )" | grep -q .; then fail "UDP $WIREGUARD_PORT is already in use."; fi
    if [[ "$FLUXER_ENABLED" == yes ]]; then
        if ss -H -ltn '( sport = :7881 )' | grep -q .; then fail 'Fluxer TCP 7881 is already in use.'; fi
        if ss -H -lun '( sport = :7882 )' | grep -q .; then fail 'Fluxer UDP 7882 is already in use.'; fi
    fi
    mountpoint -q "$BACKUP_MOUNT" || fail 'Mount your separate backup disk first.'
    [[ "$(stat -c %d "$BACKUP_MOUNT")" != "$(stat -c %d /srv)" ]] || fail 'Backup disk must be a different filesystem from /srv.'
    [[ ! -e "$DEPLOY_DIR/.env" ]] || fail 'DEN is already configured.'
    [[ ! -d "$DATA_DIR" || -z "$(find "$DATA_DIR" -mindepth 1 -print -quit)" ]] || fail '/srv/den is not empty; use recovery instead.'
    check_media_disk
    if [[ -n "${MEDIA_MOUNT:-}" ]]; then
        for flag in media downloads; do
            [[ ! -L "$MEDIA_MOUNT/den" && ! -L "$MEDIA_MOUNT/den/$flag" ]] || fail 'Secondary storage folders cannot be symlinks.'
            [[ ! -d "$MEDIA_MOUNT/den/$flag" || -z "$(find "$MEDIA_MOUNT/den/$flag" -mindepth 1 -print -quit)" ]] || fail 'Secondary DEN media/downloads are not empty; use an explicit recovery or migration.'
        done
    fi
}

write_vpn() {
    local server_key client_key public_key client_public
    umask 077
    server_key="$(wg genkey)"; client_key="$(wg genkey)"
    public_key="$(printf '%s' "$server_key" | wg pubkey)"
    client_public="$(printf '%s' "$client_key" | wg pubkey)"
    mkdir -p "$DEPLOY_DIR/private"
    cat > "$DEPLOY_DIR/private/wg0.conf" <<EOF
[Interface]
Address = 10.44.0.1/24
ListenPort = $WIREGUARD_PORT
PrivateKey = $server_key
PostUp = iptables -I FORWARD 1 -i %i -d $LAN_CIDR -j ACCEPT; iptables -I FORWARD 1 -o %i -s $LAN_CIDR -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.44.0.0/24 -d $LAN_CIDR -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -d $LAN_CIDR -j ACCEPT; iptables -D FORWARD -o %i -s $LAN_CIDR -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.44.0.0/24 -d $LAN_CIDR -j MASQUERADE

[Peer]
PublicKey = $client_public
AllowedIPs = 10.44.0.2/32
EOF
    cat > "$DEPLOY_DIR/private/home.conf" <<EOF
[Interface]
PrivateKey = $client_key
Address = 10.44.0.2/32
DNS = 10.44.0.1

[Peer]
PublicKey = $public_key
Endpoint = vpn.$DOMAIN:$WIREGUARD_PORT
AllowedIPs = 10.44.0.0/24, $LAN_CIDR
PersistentKeepalive = 25
EOF
    write_vpn_dns > "$DEPLOY_DIR/private/dnsmasq.conf"
    chmod 700 "$DEPLOY_DIR/private"
    chmod 600 "$DEPLOY_DIR/private/"*.conf
}

write_vpn_dns() {
    local name
    cat <<EOF
port=53
listen-address=10.44.0.1
bind-interfaces
no-resolv
server=1.1.1.1
server=1.0.0.1
EOF
    for name in home media photos files git; do
        printf 'host-record=%s.%s,%s\n' "$name" "$DOMAIN" "$LAN_IP"
    done
    if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then
        printf 'host-record=chat.%s,%s\n' "$DOMAIN" "$LAN_IP"
    fi
    if [[ "${QBITTORRENT_ENABLED:-no}" == yes ]]; then
        printf 'host-record=downloads.%s,%s\n' "$DOMAIN" "$LAN_IP"
    fi
    if [[ "${AI_ENABLED:-no}" == yes ]]; then
        printf 'host-record=ai.%s,%s\n' "$DOMAIN" "$LAN_IP"
    fi
    if [[ -f "$DEPLOY_DIR/private/external-edge" && -f "$DEPLOY_DIR/private/infrastructure/compose.yml" ]]; then
        printf 'host-record=dns.%s,%s\n' "$DOMAIN" "$LAN_IP"
    fi
}

install_host_config() {
    install -d -m 700 /etc/wireguard
    install -m 600 "$DEPLOY_DIR/private/wg0.conf" /etc/wireguard/wg0.conf
    install_login_banner || fail 'Could not install the DEN login banner.'
    printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/90-den.conf
    sysctl -p /etc/sysctl.d/90-den.conf
    configure_fedora_host
    install -m 644 "$DEPLOY_DIR/templates/systemd/"* /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now wg-quick@wg0 den-dns
    systemctl enable den.service
    configure_nvidia_power || return 1
    systemctl enable --now den-ddns.timer
}

start_stack() {
    local -a services=()
    ai_start || return 1
    if [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes ]] && ! torrent_vpn_profile_ready; then
        log 'Torrent VPN profile is missing: qBittorrent remains stopped. Import it with den torrent-vpn /absolute/path.conf.'
        compose stop --timeout 120 qbittorrent torrent-vpn || return 1
        mapfile -t services < <(compose config --services | grep -Ev '^(qbittorrent|torrent-vpn)$')
        [[ ${#services[@]} -gt 0 ]] || fail 'Could not identify services to start without the torrent VPN.'
    fi
    compose up -d --wait --wait-timeout 900 "${services[@]}" || return 1
    compose exec -T -u www-data nextcloud php occ background:cron
}

show_summary() {
    setup_section 'DEN setup complete - next steps'
    printf '\nHome: https://home.%s\nMedia: https://media.%s\nPhotos: https://photos.%s\nFiles: https://files.%s\nGit: https://git.%s\n' "$DOMAIN" "$DOMAIN" "$DOMAIN" "$DOMAIN" "$DOMAIN"
    if [[ -f "$DEPLOY_DIR/private/external-edge" && -f "$DEPLOY_DIR/private/infrastructure/compose.yml" ]]; then
        printf 'DNS administration: https://dns.%s (trusted LAN/VPN).\n' "$DOMAIN"
    fi
    if [[ -n "${TV_CIDR:-}" ]]; then
        printf 'TV network: %s (DNS and Jellyfin HTTPS; router isolation required).\n' "$TV_CIDR"
    fi
    printf '\nNextcloud user: admin. Password: sudo grep NEXTCLOUD_ADMIN_PASSWORD /opt/den/.env\n'
    printf 'VPN profile: /opt/den/private/home.conf (private; use on ONE device).\n'
    printf "Show its private QR code over SSH: sudo sh -c 'qrencode -t ansiutf8 < /opt/den/private/home.conf'\n"
    printf 'Finish Jellyfin and Immich account setup in your browser. Create Git admin with: sudo den git-admin\n'
    printf 'Save the recovery kit away from this server: sudo den recovery-kit /path/on/another/device\n'
    if [[ -n "${MEDIA_MOUNT:-}" ]]; then
        printf 'HDD media/downloads: %s/den (mounted at /srv/den/media and /srv/den/downloads).\n' "$MEDIA_MOUNT"
    fi
    if [[ "${KEEPASS_ENABLED:-no}" == yes ]]; then
        printf 'KeePass vault: /opt/den/vaults/admin/credentials.kdbx; retrieve its password separately with: sudo den keepass-password\n'
    fi
    if [[ "${AI_ENABLED:-no}" == yes ]]; then
        printf 'AI: https://ai.%s (LAN/VPN only; select DEN or optional workstation model).\n' "$DOMAIN"
        printf 'Initial AI login: EMAIL from .env; password in /opt/den/private/ai-webui.env. Change it in WebUI.\n'
    fi
    if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then
        printf 'Fluxer: https://chat.%s (PUBLIC chat/calls; registration by invite).\n' "$DOMAIN"
        printf 'Forward TCP 443/7881 and UDP 7882 to DEN, plus TCP 80 for HTTP certificates. Voice uses automatic public-IP discovery.\n'
    fi
    if [[ "${QBITTORRENT_ENABLED:-no}" == yes ]]; then
        printf 'Downloads: https://downloads.%s (qBittorrent admin; temporary password in sudo den logs qbittorrent).\n' "$DOMAIN"
        if [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes ]]; then
            printf 'Torrent-only WireGuard required (kill switch; no direct fallback). Profile: /opt/den/private/torrent-vpn/wg0.conf.\n'
            if ! torrent_vpn_profile_ready; then
                printf 'BLOCKED pending profile: sudo den torrent-vpn /absolute/path/to/provider.conf\n'
            fi
        else
            printf 'Direct mode: trackers/peers see your normal public IP. Optional protection: sudo den torrent-vpn /path/to/provider.conf\n'
        fi
        printf 'Set a permanent Web UI password. Do not forward torrent ports or enable UPnP.\n'
    fi
}

validate_peer_name() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{0,29}$ && "$1" != wg0 && "$1" != dnsmasq ]] || fail 'Use a short lowercase device name (not wg0 or dnsmasq).'
}

vpn_add() {
    local name="$1" address key public server_public profile
    validate_peer_name "$name"
    profile="$DEPLOY_DIR/private/$name.conf"
    [[ ! -e "$profile" ]] || fail 'Device name already exists.'
    address="$(awk '$1 == "AllowedIPs" {split($3, parts, /[.\/]/); if (parts[4] > highest) highest=parts[4]} END {print highest+1}' "$DEPLOY_DIR/private/wg0.conf")"
    (( address >= 2 && address <= 254 )) || fail 'VPN address pool is full.'
    key="$(wg genkey)"; public="$(printf '%s' "$key" | wg pubkey)"
    server_public="$(wg show wg0 public-key)"
    umask 077
    cat > "$profile" <<EOF
[Interface]
PrivateKey = $key
Address = 10.44.0.$address/32
DNS = 10.44.0.1

[Peer]
PublicKey = $server_public
Endpoint = vpn.$DOMAIN:$WIREGUARD_PORT
AllowedIPs = 10.44.0.0/24, $LAN_CIDR
PersistentKeepalive = 25
EOF
    if ! wg set wg0 peer "$public" allowed-ips "10.44.0.$address/32"; then
        rm -f "$profile"
        return 1
    fi
    printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.44.0.%s/32\n' "$public" "$address" >> "$DEPLOY_DIR/private/wg0.conf"
    install -m 600 "$DEPLOY_DIR/private/wg0.conf" /etc/wireguard/wg0.conf
    log "Private profile created: $profile. Import it on ONE device, then run den backup."
}

vpn_remove() {
    local name="$1" profile public temporary
    validate_peer_name "$name"
    profile="$DEPLOY_DIR/private/$name.conf"
    [[ -f "$profile" ]] || fail 'Device profile not found.'
    public="$(awk '$1 == "PrivateKey" {print $3}' "$profile" | wg pubkey)"
    temporary="$(mktemp "$DEPLOY_DIR/private/wg0.XXXXXX")"
    awk -v public="$public" 'BEGIN {RS=""; ORS="\n\n"} !index($0, "PublicKey = " public) {print}' \
        "$DEPLOY_DIR/private/wg0.conf" > "$temporary"
    wg set wg0 peer "$public" remove
    mv "$temporary" "$DEPLOY_DIR/private/wg0.conf"
    install -m 600 "$DEPLOY_DIR/private/wg0.conf" /etc/wireguard/wg0.conf
    rm -f "$profile"
    log 'VPN device revoked. Remove any copies of its profile and take a new backup.'
}