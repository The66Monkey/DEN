#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'DEN: %s\n' "$*" >&2; exit 1; }
log() { printf 'DEN: %s\n' "$*"; }

# Deliberately uncommon ports for everything DEN itself chooses. TCP 80/443 stay
# standard (HTTP-01 and default HTTPS URLs), and Fluxer's voice ports are upstream's.
WIREGUARD_PORT=41873
QBITTORRENT_WEBUI_PORT=18427
QBITTORRENT_PEER_PORT=36419
FLUXER_PROXY_PORT=29461

read_settings() {
    local file="$1" line key value
    local -A seen=()
    [[ -f "$file" ]] || fail "Config not found: $file"
    unset DOMAIN EMAIL LAN_IP LAN_CIDR MEDIA_MOUNT BACKUP_MOUNT ALLOW_SHARED_MEDIA_BACKUP KEEPASS_ENABLED FLUXER_ENABLED QBITTORRENT_ENABLED QBITTORRENT_VPN_ENABLED UPDATE_REPOSITORY ACME_CHALLENGE DB_PASSWORD NEXTCLOUD_ADMIN_PASSWORD RESTIC_PASSWORD
    MEDIA_MOUNT=
    ALLOW_SHARED_MEDIA_BACKUP=no
    ACME_CHALLENGE=http
    KEEPASS_ENABLED=no
    FLUXER_ENABLED=no
    QBITTORRENT_ENABLED=no
    QBITTORRENT_VPN_ENABLED=no
    AI_ENABLED=no
    AI_MODEL=llama3.2:3b
    AI_REMOTE_OLLAMA_URL=
    NVIDIA_POWER_LIMIT_W=
    NVIDIA_GPU_ID=0
    UPDATE_REPOSITORY=https://github.com/The66Monkey/DEN.git
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || fail 'Use unquoted KEY=value lines in config.'
        key="${line%%=*}"; value="${line#*=}"
        case "$key" in
            DOMAIN|EMAIL|LAN_IP|LAN_CIDR|MEDIA_MOUNT|BACKUP_MOUNT|ALLOW_SHARED_MEDIA_BACKUP|KEEPASS_ENABLED|FLUXER_ENABLED|QBITTORRENT_ENABLED|QBITTORRENT_VPN_ENABLED|AI_ENABLED|AI_MODEL|AI_REMOTE_OLLAMA_URL|NVIDIA_POWER_LIMIT_W|NVIDIA_GPU_ID|UPDATE_REPOSITORY|ACME_CHALLENGE|DB_PASSWORD|NEXTCLOUD_ADMIN_PASSWORD|RESTIC_PASSWORD) ;;
            *) fail "Unknown config key: $key" ;;
        esac
        [[ ! -v "seen[$key]" ]] || fail "Duplicate config key: $key"
        seen[$key]=1
        printf -v "$key" '%s' "$value"
    done < "$file"
    validate_settings
}

request_ddns_token() {
    local token attempt
    if [[ -n "${DESEC_TOKEN_FILE:-}" ]]; then
        [[ -f "$DESEC_TOKEN_FILE" && ! -L "$DESEC_TOKEN_FILE" ]] || fail 'DESEC_TOKEN_FILE must be a regular file, not a symlink.'
        [[ "$(stat -c %u "$DESEC_TOKEN_FILE")" == "$EUID" ]] || fail 'DESEC_TOKEN_FILE must be owned by the installer user (root with sudo).'
        (( (8#$(stat -c %a "$DESEC_TOKEN_FILE") & 077) == 0 )) || fail 'DESEC_TOKEN_FILE must not be accessible to group or other users; use chmod 600.'
        (( $(stat -c %s "$DESEC_TOKEN_FILE") <= 129 )) || fail 'DESEC_TOKEN_FILE is too large.'
        token="$(cat -- "$DESEC_TOKEN_FILE")" || fail 'Could not read DESEC_TOKEN_FILE.'
        validate_desec_token "$token" || fail 'DESEC_TOKEN_FILE does not contain a valid deSEC API token.'
        DESEC_TOKEN="$token"
        return 0
    fi
    [[ -t 0 ]] || fail 'A deSEC API token is required; run the installer in an interactive terminal.'
    for attempt in 1 2 3; do
        read -r -s -p 'deSEC API token (DNS update access for this domain): ' token
        printf '\n' >&2
        if validate_desec_token "$token"; then
            DESEC_TOKEN="$token"
            return 0
        fi
        printf 'DEN: Enter a valid deSEC token (16-128 letters, digits, or ._~+/=- characters).\n' >&2
    done
    fail 'A valid deSEC API token is required for dynamic DNS updates.'
}

validate_desec_token() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._~+/=-]{16,128}$ ]]
}

validate_hostname() {
    [[ "${1:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

request_server_hostname() {
    local requested
    SERVER_HOSTNAME=FedoraDEN
    if [[ ! -t 0 ]]; then
        SERVER_HOSTNAME="$(hostname -s)" || fail 'Could not read the current server hostname.'
        return 0
    fi
    while true; do
        read -r -p "Server hostname (one label) [$SERVER_HOSTNAME]: " requested ||
            fail 'Could not read the server hostname.'
        requested="${requested:-$SERVER_HOSTNAME}"
        if validate_hostname "$requested"; then
            SERVER_HOSTNAME="$requested"
            return 0
        fi
        printf 'DEN: Use 1-63 letters, digits, or hyphens; do not start or end with a hyphen.\n' >&2
    done
}

ipv4_number() {
    local address="$1" octet result=0
    local -a octets
    [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a octets <<< "$address"
    for octet in "${octets[@]}"; do
        [[ ${#octet} -le 3 && "$octet" == "$((10#$octet))" ]] || return 1
        (( 10#$octet <= 255 )) || return 1
        result=$(( (result << 8) + 10#$octet ))
    done
    printf '%s\n' "$result"
}

validate_settings() {
    local key label address network prefix mask private=false
    for key in DOMAIN EMAIL LAN_IP LAN_CIDR BACKUP_MOUNT; do
        [[ -n "${!key:-}" ]] || fail "Missing config key: $key"
    done
    [[ "$KEEPASS_ENABLED" == yes || "$KEEPASS_ENABLED" == no ]] || fail 'KEEPASS_ENABLED must be yes or no.'
    [[ "${AI_ENABLED:-no}" == yes || "${AI_ENABLED:-no}" == no ]] || fail 'AI_ENABLED must be yes or no.'
    [[ "${AI_MODEL:-llama3.2:3b}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,127}$ ]] || fail 'AI_MODEL must be an Ollama model name without whitespace.'
    [[ -z "${AI_REMOTE_OLLAMA_URL:-}" || "$AI_REMOTE_OLLAMA_URL" =~ ^http://127\.0\.0\.1:([1-9][0-9]{0,4})$ ]] || fail 'AI_REMOTE_OLLAMA_URL must be an HTTP localhost SSH-tunnel endpoint with an explicit port.'
    if [[ -n "${AI_REMOTE_OLLAMA_URL:-}" ]]; then
        (( ${AI_REMOTE_OLLAMA_URL##*:} <= 65535 )) || fail 'AI remote port is out of range.'
        [[ "${AI_REMOTE_OLLAMA_URL##*:}" != 11435 ]] || fail 'AI remote endpoint conflicts with DEN Ollama.'
    fi
    [[ -z "${NVIDIA_POWER_LIMIT_W:-}" || "$NVIDIA_POWER_LIMIT_W" =~ ^[1-9][0-9]{1,2}$ ]] || fail 'NVIDIA_POWER_LIMIT_W must be empty or a whole number from 10 to 999.'
    [[ "${NVIDIA_GPU_ID:-0}" =~ ^([0-9]+|GPU-[a-fA-F0-9-]+)$ ]] || fail 'NVIDIA_GPU_ID must be an index or GPU UUID.'
    [[ "$FLUXER_ENABLED" == yes || "$FLUXER_ENABLED" == no ]] || fail 'FLUXER_ENABLED must be yes or no.'
    [[ "$QBITTORRENT_ENABLED" == yes || "$QBITTORRENT_ENABLED" == no ]] || fail 'QBITTORRENT_ENABLED must be yes or no.'
    [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes || "${QBITTORRENT_VPN_ENABLED:-no}" == no ]] || fail 'QBITTORRENT_VPN_ENABLED must be yes or no.'
    [[ "${QBITTORRENT_VPN_ENABLED:-no}" != yes || "$QBITTORRENT_ENABLED" == yes ]] || fail 'Enable qBittorrent before its outbound VPN.'
    [[ "${ALLOW_SHARED_MEDIA_BACKUP:-no}" == yes || "${ALLOW_SHARED_MEDIA_BACKUP:-no}" == no ]] || fail 'ALLOW_SHARED_MEDIA_BACKUP must be yes or no.'
    [[ "${ACME_CHALLENGE:-http}" == http || "${ACME_CHALLENGE:-http}" == dns-desec ]] || fail 'ACME_CHALLENGE must be http or dns-desec.'
    [[ "$UPDATE_REPOSITORY" =~ ^https://[a-zA-Z0-9.-]+/[a-zA-Z0-9._/-]+\.git$ || "$UPDATE_REPOSITORY" =~ ^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+\.git$ ]] || fail 'UPDATE_REPOSITORY must be an HTTPS or SSH Git repository URL without embedded credentials.'
    [[ ${#DOMAIN} -le 253 && "$DOMAIN" == *.* && "$DOMAIN" != *.local && "$DOMAIN" != *.localhost ]] || fail 'Use a public DNS domain.'
    local -a labels
    IFS=. read -r -a labels <<< "$DOMAIN"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || fail 'Domain must contain lowercase DNS labels.'
    done
    [[ "$DOMAIN" != *. && "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || fail 'Invalid domain or email.'
    address="$(ipv4_number "$LAN_IP")" || fail 'Invalid LAN_IP.'
    [[ "$LAN_CIDR" == */* ]] || fail 'LAN_CIDR must include a prefix.'
    prefix="${LAN_CIDR##*/}"
    [[ "$prefix" =~ ^(8|9|[12][0-9]|30)$ ]] || fail 'LAN_CIDR must use a prefix from 8 to 30.'
    network="$(ipv4_number "${LAN_CIDR%/*}")" || fail 'Invalid LAN_CIDR.'
    mask=$(( (0xffffffff << (32 - prefix)) & 0xffffffff ))
    (( (network & mask) == network && (address & mask) == network )) || fail 'LAN_IP must belong to a canonical LAN_CIDR.'
    (( address != network && address != (network | (0xffffffff ^ mask)) )) || fail 'LAN_IP cannot be a network or broadcast address.'
    if (( (network >> 24) == 10 && prefix >= 8 )); then private=true; fi
    if (( (network >> 20) == 2753 && prefix >= 12 )); then private=true; fi
    if (( (network >> 16) == 49320 && prefix >= 16 )); then private=true; fi
    [[ "$private" == true ]] || fail 'LAN_CIDR must be an RFC1918 private subnet.'
    (( (network & mask) != (170655744 & mask) )) || fail 'LAN overlaps the DEN VPN subnet (10.44.0.0/24).'
    (( (network & mask) != (((172 << 24) | (30 << 16) | (44 << 8)) & mask) )) || fail 'LAN overlaps the DEN container subnet (172.30.44.0/24).'
    [[ "$BACKUP_MOUNT" =~ ^/mnt/[a-zA-Z0-9_-]+$ || "$BACKUP_MOUNT" =~ ^/media/[a-zA-Z0-9_-]+$ ]] || fail 'BACKUP_MOUNT must be a simple absolute path under /mnt or /media.'
    if [[ -n "${MEDIA_MOUNT:-}" ]]; then
        [[ "$MEDIA_MOUNT" =~ ^/mnt/[a-zA-Z0-9_-]+$ ]] || fail 'MEDIA_MOUNT must be a simple absolute path under /mnt, or empty for single-disk storage.'
        [[ "$MEDIA_MOUNT" != "$BACKUP_MOUNT" || "${ALLOW_SHARED_MEDIA_BACKUP:-no}" == yes ]] || fail 'Media and backup disks must be separate unless ALLOW_SHARED_MEDIA_BACKUP=yes.'
    fi
    for key in DB_PASSWORD NEXTCLOUD_ADMIN_PASSWORD RESTIC_PASSWORD; do
        [[ ! -v "$key" || "${!key}" =~ ^[a-f0-9]{48}$ ]] || fail "Invalid generated secret: $key"
    done
}

write_environment() {
    local destination="$1" key
    validate_desec_token "${DESEC_TOKEN:-}" || fail 'A valid deSEC API token is required.'
    mkdir -p "$destination" "$destination/private"
    chmod 700 "$destination"
    if [[ -f "$destination/.env" ]]; then
        fail 'An environment already exists; use den start, not a second install.'
    fi
    umask 077
    DB_PASSWORD="$(openssl rand -hex 24)"
    NEXTCLOUD_ADMIN_PASSWORD="$(openssl rand -hex 24)"
    RESTIC_PASSWORD="$(openssl rand -hex 24)"
    ALLOW_SHARED_MEDIA_BACKUP="${ALLOW_SHARED_MEDIA_BACKUP:-no}"
    for key in DOMAIN EMAIL LAN_IP LAN_CIDR MEDIA_MOUNT BACKUP_MOUNT ALLOW_SHARED_MEDIA_BACKUP KEEPASS_ENABLED FLUXER_ENABLED QBITTORRENT_ENABLED QBITTORRENT_VPN_ENABLED AI_ENABLED AI_MODEL AI_REMOTE_OLLAMA_URL NVIDIA_POWER_LIMIT_W NVIDIA_GPU_ID UPDATE_REPOSITORY ACME_CHALLENGE; do
        printf '%s=%s\n' "$key" "${!key}"
    done > "$destination/.env"
    printf 'DB_PASSWORD=%s\nNEXTCLOUD_ADMIN_PASSWORD=%s\nRESTIC_PASSWORD=%s\n' \
        "$DB_PASSWORD" "$NEXTCLOUD_ADMIN_PASSWORD" "$RESTIC_PASSWORD" >> "$destination/.env"
    chmod 600 "$destination/.env"
    printf 'DOMAIN=%s\nFLUXER_ENABLED=%s\nQBITTORRENT_ENABLED=%s\nDESEC_TOKEN=%s\n' \
        "$DOMAIN" "$FLUXER_ENABLED" "$QBITTORRENT_ENABLED" "$DESEC_TOKEN" > "$destination/private/ddns.env"
    chmod 600 "$destination/private/ddns.env"
    if [[ "$ACME_CHALLENGE" == dns-desec ]]; then
        printf '%s\n' "$DESEC_TOKEN" > "$destination/private/desec-token"
        chmod 600 "$destination/private/desec-token"
    fi
}