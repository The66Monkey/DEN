#!/usr/bin/env bash

compose() {
    env -i PATH="$PATH" HOME="${HOME:-/root}" docker compose \
        --project-name den --project-directory "$DEPLOY_DIR" \
        --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/compose.yml" "$@"
}

write_routes() {
    jq -n --arg domain "$DOMAIN" --arg lan "$LAN_CIDR" '
        {http: {
            middlewares: {
                private: {ipAllowList: {sourceRange: [$lan, "10.44.0.0/24"]}},
                headers: {headers: {contentTypeNosniff: true, referrerPolicy: "same-origin"}},
                dav: {redirectRegex: {
                    regex: "https://(.*)/.well-known/(?:card|cal)dav",
                    replacement: "https://${1}/remote.php/dav/", permanent: true}}
            },
            routers: (reduce ["media", "photos", "files", "git"][] as $name ({};
                .[$name] = {rule: ("Host(`" + $name + "." + $domain + "`)") ,
                    entryPoints: ["websecure"], service: $name,
                    middlewares: (["private", "headers"] + (if $name == "files" then ["dav"] else [] end)),
                    tls: {certResolver: "home"}})),
            services: {
                media: {loadBalancer: {servers: [{url: "http://jellyfin:8096"}]}},
                photos: {loadBalancer: {servers: [{url: "http://immich-server:2283"}]}},
                files: {loadBalancer: {servers: [{url: "http://nextcloud:80"}]}},
                git: {loadBalancer: {servers: [{url: "http://forgejo:3000"}]}}
            }
        }}' > "$DEPLOY_DIR/routes.json"
}

prepare_storage() {
    local directory
    [[ ! -L "$DATA_DIR" && ! -L "$DEPLOY_DIR" ]] || fail 'DEN roots cannot be symlinks.'
    mkdir -p "$DATA_DIR"
    chmod 755 "$DATA_DIR"
    for directory in traefik jellyfin media/movies media/tv media/music cache/jellyfin cache/immich immich/library immich/database nextcloud/html nextcloud/database forgejo system; do
        mkdir -p "$DATA_DIR/$directory"
    done
    chmod 700 "$DATA_DIR/system" "$DATA_DIR/traefik"
    chown 1000:1000 "$DATA_DIR/jellyfin" "$DATA_DIR/cache/jellyfin" "$DATA_DIR/media" "$DATA_DIR/media/"* "$DATA_DIR/forgejo"
    [[ -f "$DATA_DIR/traefik/acme.json" ]] || install -m 600 /dev/null "$DATA_DIR/traefik/acme.json"
}

check_host() {
    [[ "$EUID" == 0 ]] || fail 'Run installation with sudo.'
    local ID VERSION_ID flag memory
    source /etc/os-release
    [[ "$ID" == debian && "$VERSION_ID" == 13 ]] || fail 'DEN currently targets Debian 13 Stable only.'
    [[ "$(uname -m)" == x86_64 ]] || fail 'DEN currently tests x86_64 PCs only.'
    for flag in cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3; do
        grep -qm1 -w "$flag" /proc/cpuinfo || fail "CPU lacks $flag; Immich needs x86-64-v2 (usually 2012 or newer)."
    done
    memory="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    (( memory >= 7500000 )) || fail 'At least 8 GB RAM is required; 16 GB is recommended.'
    ip -4 -o address show | grep -Fq " $LAN_IP/" || fail 'LAN_IP is not assigned to this server.'
    [[ ! -e /etc/wireguard/wg0.conf && ! -e /etc/systemd/system/den.service ]] || fail 'Existing wg0 or DEN installation found.'
    if ss -H -ltn '( sport = :80 or sport = :443 )' | grep -q .; then fail 'TCP 80/443 is already in use.'; fi
    if ss -H -lun '( sport = :51820 )' | grep -q .; then fail 'UDP 51820 is already in use.'; fi
    mountpoint -q "$BACKUP_MOUNT" || fail 'Mount your separate backup disk first.'
    [[ "$(stat -c %d "$BACKUP_MOUNT")" != "$(stat -c %d /srv)" ]] || fail 'Backup disk must be a different filesystem from /srv.'
    [[ ! -e "$DEPLOY_DIR/.env" ]] || fail 'DEN is already configured.'
    [[ ! -d "$DATA_DIR" || -z "$(find "$DATA_DIR" -mindepth 1 -print -quit)" ]] || fail '/srv/den is not empty; use recovery instead.'
}

install_packages() {
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose restic wireguard-tools dnsmasq-base iptables jq openssl curl ca-certificates
    systemctl enable --now docker
    docker compose version >/dev/null
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
ListenPort = 51820
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
Endpoint = $DOMAIN:51820
AllowedIPs = 10.44.0.0/24, $LAN_CIDR
PersistentKeepalive = 25
EOF
    cat > "$DEPLOY_DIR/private/dnsmasq.conf" <<EOF
port=53
listen-address=10.44.0.1
bind-interfaces
no-resolv
server=1.1.1.1
server=1.0.0.1
address=/$DOMAIN/$LAN_IP
local=/$DOMAIN/
EOF
    chmod 700 "$DEPLOY_DIR/private"
    chmod 600 "$DEPLOY_DIR/private/"*.conf
}

install_host_config() {
    install -d -m 700 /etc/wireguard
    install -m 600 "$DEPLOY_DIR/private/wg0.conf" /etc/wireguard/wg0.conf
    printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/90-den.conf
    sysctl -p /etc/sysctl.d/90-den.conf
    install -m 644 "$DEPLOY_DIR/templates/systemd/"* /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now wg-quick@wg0 den-dns
    systemctl enable den.service
}

start_stack() {
    compose up -d --wait --wait-timeout 900 || return 1
    compose exec -T -u www-data nextcloud php occ background:cron
}

show_summary() {
    printf '\nMedia: https://media.%s\nPhotos: https://photos.%s\nFiles: https://files.%s\nGit: https://git.%s\n' "$DOMAIN" "$DOMAIN" "$DOMAIN" "$DOMAIN"
    printf '\nNextcloud user: admin. Password: sudo grep NEXTCLOUD_ADMIN_PASSWORD /opt/den/.env\n'
    printf 'VPN profile: /opt/den/private/home.conf (private; use on ONE device).\n'
    printf 'Finish Jellyfin and Immich account setup in your browser. Create Git admin with: sudo den git-admin\n'
    printf 'Save the recovery kit away from this server: sudo den recovery-kit /path/on/another/device\n'
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
Endpoint = $DOMAIN:51820
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