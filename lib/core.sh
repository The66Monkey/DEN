#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'DEN: %s\n' "$*" >&2; exit 1; }
log() { printf 'DEN: %s\n' "$*"; }

read_settings() {
    local file="$1" line key value
    local -A seen=()
    [[ -f "$file" ]] || fail "Config not found: $file"
    unset DOMAIN EMAIL LAN_IP LAN_CIDR MEDIA_MOUNT BACKUP_MOUNT KEEPASS_ENABLED FLUXER_ENABLED QBITTORRENT_ENABLED UPDATE_REPOSITORY DB_PASSWORD NEXTCLOUD_ADMIN_PASSWORD RESTIC_PASSWORD
    MEDIA_MOUNT=
    KEEPASS_ENABLED=no
    FLUXER_ENABLED=no
    QBITTORRENT_ENABLED=no
    UPDATE_REPOSITORY=https://github.com/The66Monkey/DEN.git
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || fail 'Use unquoted KEY=value lines in config.'
        key="${line%%=*}"; value="${line#*=}"
        case "$key" in
            DOMAIN|EMAIL|LAN_IP|LAN_CIDR|MEDIA_MOUNT|BACKUP_MOUNT|KEEPASS_ENABLED|FLUXER_ENABLED|QBITTORRENT_ENABLED|UPDATE_REPOSITORY|DB_PASSWORD|NEXTCLOUD_ADMIN_PASSWORD|RESTIC_PASSWORD) ;;
            *) fail "Unknown config key: $key" ;;
        esac
        [[ ! -v "seen[$key]" ]] || fail "Duplicate config key: $key"
        seen[$key]=1
        printf -v "$key" '%s' "$value"
    done < "$file"
    validate_settings
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
    [[ "$FLUXER_ENABLED" == yes || "$FLUXER_ENABLED" == no ]] || fail 'FLUXER_ENABLED must be yes or no.'
    [[ "$QBITTORRENT_ENABLED" == yes || "$QBITTORRENT_ENABLED" == no ]] || fail 'QBITTORRENT_ENABLED must be yes or no.'
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
        [[ "$MEDIA_MOUNT" != "$BACKUP_MOUNT" ]] || fail 'Media and backup disks must be separate.'
    fi
    for key in DB_PASSWORD NEXTCLOUD_ADMIN_PASSWORD RESTIC_PASSWORD; do
        [[ ! -v "$key" || "${!key}" =~ ^[a-f0-9]{48}$ ]] || fail "Invalid generated secret: $key"
    done
}

write_environment() {
    local destination="$1" key
    mkdir -p "$destination"
    chmod 700 "$destination"
    if [[ -f "$destination/.env" ]]; then
        fail 'An environment already exists; use den start, not a second install.'
    fi
    umask 077
    DB_PASSWORD="$(openssl rand -hex 24)"
    NEXTCLOUD_ADMIN_PASSWORD="$(openssl rand -hex 24)"
    RESTIC_PASSWORD="$(openssl rand -hex 24)"
    for key in DOMAIN EMAIL LAN_IP LAN_CIDR MEDIA_MOUNT BACKUP_MOUNT KEEPASS_ENABLED FLUXER_ENABLED QBITTORRENT_ENABLED UPDATE_REPOSITORY; do
        printf '%s=%s\n' "$key" "${!key}"
    done > "$destination/.env"
    printf 'DB_PASSWORD=%s\nNEXTCLOUD_ADMIN_PASSWORD=%s\nRESTIC_PASSWORD=%s\n' \
        "$DB_PASSWORD" "$NEXTCLOUD_ADMIN_PASSWORD" "$RESTIC_PASSWORD" >> "$destination/.env"
    chmod 600 "$destination/.env"
}