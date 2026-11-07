#!/usr/bin/env bash

cockpit_configure() (
    set -euo pipefail
    local config_dir="${DEN_COCKPIT_CONFIG_DIR:-/etc/cockpit}"
    local systemd_dir="${DEN_COCKPIT_SYSTEMD_DIR:-/etc/systemd/system}"
    local state="$DEPLOY_DIR/private/cockpit-state" candidate file cert_public key_public
    local config="$config_dir/cockpit.conf" socket="$systemd_dir/cockpit.socket.d/den.conf"
    install -d -m 700 "$state" || return 1
    install -d -m 755 "$DEPLOY_DIR/private/cockpit" || return 1
    [[ ! -L "$config" && ! -L "$socket" ]] || fail 'Cockpit integration files cannot be symlinks.'
    if [[ -f "$state/managed.conf" && "${DEN_COCKPIT_RECOVERY:-no}" != yes ]]; then
        cmp -s "$config" "$state/managed.conf" || fail 'Cockpit configuration changed outside DEN; reconcile it before cockpit-setup.'
        cmp -s "$socket" "$state/managed.socket" || fail 'Cockpit socket changed outside DEN; reconcile it before cockpit-setup.'
    fi
    if [[ "${COCKPIT_ENABLED:-yes}" == no ]]; then
        if [[ -f "$state/managed.conf" ]]; then
            if [[ -f "$state/original.conf" ]]; then
                install -m 644 "$state/original.conf" "$config" || return 1
            else
                rm -f "$config" || return 1
            fi
            rm -f "$state/managed.conf" "$state/managed.socket" "$socket" "$config_dir/ws-certs.d/99-den.cert" "$config_dir/ws-certs.d/99-den.key" || return 1
            systemctl stop cockpit.service cockpit.socket || return 1
            systemctl daemon-reload || return 1
            systemctl start cockpit.socket || return 1
        fi
        cockpit_sync_dns || return 1
        return 0
    fi
    for file in "$systemd_dir/cockpit.socket.d/"*.conf; do
        [[ ! -e "$file" || "$file" == "$socket" ]] ||
            fail "Existing Cockpit socket override requires explicit migration: $file"
    done
    if [[ ! -f "$state/managed.conf" && -e "$socket" ]]; then
        fail 'Cockpit socket file den.conf is already in use; migrate it before enabling DEN integration.'
    fi
    dnf install -y cockpit cockpit-packagekit || return 1
    install -d -m 755 "$config_dir/ws-certs.d" "$systemd_dir/cockpit.socket.d" || return 1
    if [[ ! -f "$state/managed.conf" ]]; then
        [[ ! -e "$config_dir/ws-certs.d/99-den.cert" && ! -e "$config_dir/ws-certs.d/99-den.key" ]] ||
            fail 'Cockpit certificate name 99-den is already in use; migrate it before enabling DEN integration.'
    fi
    for file in "$config_dir/ws-certs.d/"*.cert "$config_dir/ws-certs.d/"*.crt; do
        [[ ! -e "$file" || "${file##*/}" < 99-den.cert || "${file##*/}" == 99-den.cert ]] ||
            fail "Cockpit certificate sorts after DEN's backend certificate: $file"
    done
    if [[ ! -f "$state/managed.conf" && -f "$config" ]]; then
        install -m 600 "$config" "$state/original.conf" || return 1
    elif [[ ! -f "$state/managed.conf" ]]; then
        rm -f "$state/original.conf" || return 1
    fi
    candidate="$(mktemp)" || return 1
    trap 'rm -f "$candidate"' EXIT
    python3 "$DEPLOY_DIR/templates/configure-cockpit.py" "$state/original.conf" "$DOMAIN" > "$candidate" || return 1
    if [[ ! -f "$state/backend.crt" ]]; then
        openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
            -subj /CN=den-cockpit -addext subjectAltName=DNS:den-cockpit \
            -keyout "$state/backend.key" -out "$state/backend.crt" || return 1
        chmod 600 "$state/backend.key" || return 1
    fi
    openssl x509 -checkend 86400 -noout -in "$state/backend.crt" ||
        fail 'Cockpit backend certificate expires soon; replace the private backend certificate and key before cockpit-setup.'
    openssl verify -CAfile "$state/backend.crt" -verify_hostname den-cockpit "$state/backend.crt" ||
        fail 'Cockpit backend certificate must be valid for den-cockpit.'
    cert_public="$(openssl x509 -pubkey -noout -in "$state/backend.crt")" || return 1
    key_public="$(openssl pkey -pubout -in "$state/backend.key")" || return 1
    [[ "$cert_public" == "$key_public" ]] || fail 'Cockpit backend certificate and key do not match.'
    install -m 644 "$state/backend.crt" "$DEPLOY_DIR/private/cockpit/ca.crt" || return 1
    install -m 644 "$state/backend.crt" "$config_dir/ws-certs.d/99-den.cert" || return 1
    install -m 600 "$state/backend.key" "$config_dir/ws-certs.d/99-den.key" || return 1
    install -m 644 "$candidate" "$config" || return 1
    install -m 600 "$candidate" "$state/managed.conf" || return 1
    cat > "$socket" <<'EOF' || return 1
[Socket]
ListenStream=
ListenStream=172.30.44.1:9090
FreeBind=yes
EOF
    chmod 644 "$socket" || return 1
    install -m 600 "$socket" "$state/managed.socket" || return 1
    restorecon -R "$config_dir" || return 1
    systemctl stop cockpit.service cockpit.socket || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now cockpit.socket || return 1
    cockpit_sync_dns || return 1
    cockpit_prepare_infrastructure || return 1
    if [[ -f "$DEPLOY_DIR/private/external-edge" ]]; then
        infrastructure_compose up -d --no-deps --wait edge || return 1
    fi
)

cockpit_sync_dns() {
    local candidate file
    candidate="$(mktemp)" || return 1
    for file in dnsmasq.conf ddns.env; do
        [[ -f "$DEPLOY_DIR/private/$file" ]] || continue
        if ! awk -v name="host-record=server.$DOMAIN," -v record="host-record=server.$DOMAIN,$LAN_IP" \
            -v enabled="${COCKPIT_ENABLED:-yes}" -v kind="$file" '
            kind == "dnsmasq.conf" && index($0, name) != 1 {print}
            kind == "ddns.env" && index($0, "COCKPIT_ENABLED=") != 1 {print}
            END {
                if (kind == "ddns.env") print "COCKPIT_ENABLED=" enabled
                else if (enabled == "yes") print record
            }
        ' "$DEPLOY_DIR/private/$file" > "$candidate" ||
            ! cat "$candidate" > "$DEPLOY_DIR/private/$file"; then
            rm -f "$candidate"; fail "Could not update Cockpit DNS settings: $file"
        fi
    done
    rm "$candidate"
}

cockpit_prepare_infrastructure() (
    set -euo pipefail
    local compose_file="$DEPLOY_DIR/private/infrastructure/compose.yml" candidate
    [[ -f "$DEPLOY_DIR/private/external-edge" ]] || return 0
    [[ -f "$compose_file" ]] || fail 'Cockpit infrastructure proxy Compose file is missing.'
    candidate="$(mktemp)" || return 1
    trap 'rm -f "$candidate"' EXIT
    infrastructure_compose config --format json |
        jq --arg path "$DEPLOY_DIR/private/cockpit" '
            .services.edge.volumes |=
                (map(select(.target != "/etc/traefik/cockpit")) +
                [{type: "bind", source: $path, target: "/etc/traefik/cockpit", read_only: true, bind: {selinux: "z"}}])
        ' > "$candidate" || return 1
    DEN_INFRASTRUCTURE_COMPOSE_FILE="$candidate" infrastructure_compose config --quiet || return 1
    install -m 600 "$candidate" "$compose_file" || return 1
)

cockpit_setup() {
    configure_network_guard || fail 'Could not apply Cockpit backend access policy.'
    cockpit_configure || fail 'Could not configure Cockpit integration.'
    write_routes || fail 'Could not apply Cockpit HTTPS route.'
    write_homepage || fail 'Could not update Cockpit home-page link.'
    if [[ -f "$DEPLOY_DIR/private/external-edge" ]]; then
        [[ -f "$DEPLOY_DIR/private/infrastructure/compose.yml" ]] ||
            fail 'Cockpit infrastructure proxy Compose file is missing.'
    else
        compose up -d --no-deps --wait traefik || fail 'Could not restart the DEN proxy.'
    fi
    systemctl restart den-dns || fail 'Could not restart VPN DNS.'
    systemctl start den-ddns.service || fail 'Could not update Cockpit public DNS.'
    log "Cockpit integration: ${COCKPIT_ENABLED:-yes}. LAN DNS: server.$DOMAIN -> $LAN_IP."
}
