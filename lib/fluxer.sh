#!/usr/bin/env bash

fluxer_dir() { printf '%s/fluxer' "$DEPLOY_DIR"; }
fluxer_domain() { printf 'chat.%s' "$DOMAIN"; }
fluxer_bind() { printf '172.30.44.1:%s' "$FLUXER_PROXY_PORT"; }

install_rexctl() (
    set -euo pipefail
    local directory release_json url checksum archive binary
    directory="$(mktemp -d /tmp/den-rexctl.XXXXXX)"
    trap 'rm -rf "$directory"' EXIT
    release_json="$(curl -fsSL https://fluxer.dev/rexctl/release.json)" || fail 'Could not retrieve the Fluxer release index.'
    url="$(jq -er '.assets[] | select(.os == "linux" and .arch == "amd64") | .url' <<< "$release_json")" || fail 'No Linux x86_64 rexctl release is available.'
    checksum="$(jq -er '.assets[] | select(.os == "linux" and .arch == "amd64") | .sha256' <<< "$release_json")" || fail 'The rexctl release has no checksum.'
    [[ "$url" == https://github.com/fluxerapp/fluxer/releases/download/* && "$checksum" =~ ^[a-f0-9]{64}$ ]] || fail 'Invalid rexctl release metadata.'
    archive="$directory/rexctl.tar.gz"
    curl -fsSL "$url" -o "$archive" || fail 'Could not download rexctl.'
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c - >/dev/null || fail 'rexctl checksum verification failed.'
    mkdir "$directory/unpacked"
    tar -xzf "$archive" -C "$directory/unpacked" || fail 'Could not extract rexctl.'
    binary="$(find "$directory/unpacked" -type f -name rexctl -print -quit)"
    [[ -n "$binary" ]] || fail 'The rexctl archive did not contain its executable.'
    install -m 755 "$binary" /usr/local/bin/rexctl
    install -m 755 "$binary" "$DEPLOY_DIR/private/rexctl"
)

fluxer_command() {
    [[ "${FLUXER_ENABLED:-no}" == yes ]] || fail 'Fluxer is not enabled for this DEN installation.'
    local rexctl_bin="${REXCTL_BIN:-/usr/local/bin/rexctl}"
    [[ -x "$rexctl_bin" ]] || fail 'rexctl is missing; restore or reinstall the Fluxer deployment.'
    "$rexctl_bin" --dir "$(fluxer_dir)" "$@"
}

fluxer_install() {
    [[ "${FLUXER_ENABLED:-no}" == yes ]] || return 0
    local instance_domain
    instance_domain="$(fluxer_domain)"
    [[ ! -e "$(fluxer_dir)/.rexctl" ]] || fail 'Fluxer already has instance data; use rexctl instead of reinstalling.'
    install_rexctl
    install -d -m 700 "$DATA_DIR/fluxer/backups"
    fluxer_command install --domain "$instance_domain" \
        --behind-proxy --bind "$(fluxer_bind)" --setup browser \
        --voice-ip "$LAN_IP" --open-firewall=false \
        --confirm "$instance_domain" --yes
    fluxer_command registration set invite
    fluxer_command backup location "$DATA_DIR/fluxer/backups"
    fluxer_command backup
}

fluxer_backup() {
    [[ "${FLUXER_ENABLED:-no}" == yes ]] || return 0
    install -d -m 700 "$DATA_DIR/fluxer/backups"
    fluxer_command backup location "$DATA_DIR/fluxer/backups" >/dev/null
    fluxer_command backup
}

fluxer_restore() {
    [[ "${FLUXER_ENABLED:-no}" == yes ]] || return 0
    local listing archive
    local -a backups=()
    listing="$(find "$DATA_DIR/fluxer/backups" -maxdepth 1 -type f -name '*.tar.zst' -printf '%T@ %p\n' | sort -nr)"
    [[ -n "$listing" ]] || fail 'No full Fluxer archive was restored from the DEN backup.'
    mapfile -t backups <<< "$listing"
    archive="${backups[0]#* }"
    if [[ -n "${REXCTL_BIN:-}" ]]; then
        :
    elif [[ -x "$DEPLOY_DIR/private/rexctl" ]]; then
        install -m 755 "$DEPLOY_DIR/private/rexctl" /usr/local/bin/rexctl
    else
        install_rexctl
    fi
    fluxer_command restore "$archive" --confirm "$(fluxer_domain)" --yes
    fluxer_command backup location "$DATA_DIR/fluxer/backups"
}

fluxer_health_check() {
    [[ "${FLUXER_ENABLED:-no}" == yes ]] || return 0
    curl -fsS --connect-timeout 5 --max-time 10 "http://172.30.44.1:$FLUXER_PROXY_PORT/_health" >/dev/null || fail 'Fluxer is not healthy through the DEN proxy backend.'
}

fluxer_status() {
    fluxer_command status
    fluxer_health_check
}

fluxer_upgrade() {
    [[ "${FLUXER_ENABLED:-no}" == yes ]] || fail 'Fluxer is not enabled for this DEN installation.'
    install_rexctl
    backup_stack
    fluxer_command upgrade --yes
    install -m 755 /usr/local/bin/rexctl "$DEPLOY_DIR/private/rexctl"
    backup_stack
}