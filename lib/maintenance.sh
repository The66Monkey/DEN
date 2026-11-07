#!/usr/bin/env bash

copy_release() {
    local source_dir="$1" destination="$2" item
    install -d -m 700 "$destination" || return 1
    for item in bin lib templates docs config; do
        cp -a --no-preserve=ownership,context --context "$source_dir/$item" "$destination/" || return 1
        chown -R --reference="$destination" "$destination/$item" || return 1
    done
    for item in VERSION README.md install.sh update.sh recover.sh; do
        install -m 600 "$source_dir/$item" "$destination/$item" || return 1
    done
    if [[ -d "$source_dir/migrations" ]]; then
        cp -a --no-preserve=ownership,context --context "$source_dir/migrations" "$destination/" || return 1
        chown -R --reference="$destination" "$destination/migrations" || return 1
    fi
    chmod 755 "$destination/bin/den"
}

restore_deployment() {
    local source_dir="$1" destination="$2"
    copy_release "$source_dir" "$destination" || return 1
    cp "$source_dir/.env" "$destination/.env" || return 1
    cp "$source_dir/compose.yml" "$destination/compose.yml" || return 1
    cp -a "$source_dir/private" "$destination/" || return 1
    if [[ -d "$source_dir/vaults" ]]; then
        cp -a "$source_dir/vaults" "$destination/" || return 1
    fi
}

enable_update_timer() {
    local state status=0
    state="$(systemctl is-enabled den-update.timer)" || status=$?
    case "$state" in
        masked|masked-runtime) log 'Monthly updates are explicitly masked; preserving the opt-out.' ;;
        enabled|disabled) systemctl enable --now den-update.timer || return 1 ;;
        *) fail "Cannot determine update timer state ($state, exit $status)." ;;
    esac
}

check_backup_age() {
    local snapshots="$1" newest now
    newest="$(jq -er 'sort_by(.time) | last | .time // empty' <<< "$snapshots")" ||
        fail 'No successful DEN backup exists or snapshot listing is invalid.'
    newest="$(date -d "$newest" +%s)" || fail 'Cannot parse the latest DEN backup time.'
    now="$(date +%s)" || return 1
    (( now - newest < 691200 )) || fail 'Last backup is at least 8 days old.'
}

health_check() {
    local expected actual snapshots used torrent_pending=no
    check_nvidia_driver || return 1
    ensure_media_storage
    expected="$(compose config --services | wc -l)"
    if [[ "${QBITTORRENT_VPN_ENABLED:-no}" == yes ]] && ! torrent_vpn_profile_ready; then
        expected=$((expected - 2))
        torrent_pending=yes
        log 'Torrent VPN profile is missing; qBittorrent must remain stopped. Other DEN services are checked below.'
        [[ -z "$(compose ps --status running -q qbittorrent torrent-vpn)" ]] ||
            fail 'Torrent services are unexpectedly running without the required VPN profile. Stop qBittorrent.'
    fi
    actual="$(compose ps --all --format json | jq -s 'flatten | map(select(.State == "running" and .Health == "healthy")) | length')"
    [[ "$actual" == "$expected" ]] || fail "Only $actual/$expected containers are healthy. Run sudo den status."
    if [[ -f "$DEPLOY_DIR/private/external-edge" ]]; then
        infrastructure_compose exec -T edge traefik healthcheck --ping || return 1
        infrastructure_compose exec -T dns nslookup example.com 127.0.0.1 >/dev/null || return 1
        actual="$(infrastructure_compose ps --status running --services | sort)"
        [[ "$actual" == $'dns\nedge' ]] || fail 'Shared edge or LAN DNS is down.'
    fi
    systemctl is-active --quiet wg-quick@wg0 den-dns || fail 'WireGuard or VPN DNS is down.'
    systemctl is-active --quiet den-firewall || fail 'DEN network guard is down.'
    nft list table inet den_guard >/dev/null || fail 'DEN network guard rules are missing.'
    fluxer_health_check
    addon_hook check || return 1
    ensure_backup_mount
    snapshots="$(restic_cmd snapshots --host den --tag den-v1 --json)" || return 1
    check_backup_age "$snapshots" || return 1
    used="$(df --output=pcent "$DATA_DIR" | tail -1 | tr -dc '0-9')"
    (( used < 90 )) || fail 'Data filesystem is at least 90% full.'
    if [[ -n "${MEDIA_MOUNT:-}" ]]; then
        used="$(df --output=pcent "$MEDIA_MOUNT" | tail -1 | tr -dc '0-9')"
        (( used < 90 )) || fail 'Secondary storage filesystem is at least 90% full.'
    fi
    install -d -m 755 /etc/motd.d
    if [[ "$torrent_pending" == yes ]]; then
        printf 'DEN: core checks healthy; torrents blocked awaiting a provider VPN profile.\n' > /etc/motd.d/den
        fail 'Core checks passed; qBittorrent remains blocked awaiting a provider VPN profile.'
    fi
    printf 'DEN: services healthy; recent backup present.\n' > /etc/motd.d/den
    log 'Services, VPN, backup age and free space look healthy.'
}

update_release() (
    local source_dir="$1" stage old_major new_major service old_db new_db migration active
    local -a migrations=()
    [[ ! -e "$DEPLOY_DIR/private/update-in-progress" ]] || fail 'A previous update was interrupted; resolve it before updating again.'
    source_dir="$(realpath "$source_dir")"
    [[ "$source_dir" != "$DEPLOY_DIR" && -f "$source_dir/templates/compose.yml" && -f "$source_dir/VERSION" ]] || fail 'Use a separate trusted DEN release checkout.'
    stage="$(mktemp -d /opt/den-candidate.XXXXXX)"
    trap 'rm -rf "$stage"' EXIT
    copy_release "$source_dir" "$stage" || return 1
    cp "$DEPLOY_DIR/.env" "$stage/.env" || return 1
    if [[ -f "$DEPLOY_DIR/private/external-edge" ]]; then
        install -d -m 700 "$stage/private" || return 1
        cp "$DEPLOY_DIR/private/external-edge" "$stage/private/" || return 1
    fi
    local overlay
    for overlay in compose-custom.yml compose-addon.yml; do
        if [[ -f "$DEPLOY_DIR/private/$overlay" ]]; then
            install -d -m 700 "$stage/private" || return 1
            cp "$DEPLOY_DIR/private/$overlay" "$stage/private/" || return 1
        fi
    done
    cp "$stage/templates/compose.yml" "$stage/compose.yml" || return 1
    cp "$DEPLOY_DIR/routes.json" "$stage/routes.json" || return 1
    if [[ -f "$DEPLOY_DIR/private/addon-hook" ]]; then
        grep -Fq 'addon_hook prepare' "$stage/lib/deploy.sh" ||
            fail 'Candidate release lacks installed add-on lifecycle support.'
    fi
    old_major="$(compose config --format json | jq -r '.services.nextcloud.image | split(":")[1] | split(".")[0] | tonumber')" || return 1
    new_major="$(DEPLOY_DIR="$stage" compose config --format json | jq -r '.services.nextcloud.image | split(":")[1] | split(".")[0] | tonumber')" || return 1
    (( new_major >= old_major && new_major <= old_major + 1 )) || fail 'Nextcloud requires sequential major upgrades; downgrades are not supported.'
    for service in immich-db nextcloud-db; do
        old_db="$(compose config --format json | jq -r --arg service "$service" '.services[$service].image // empty | capture(":(?<major>[0-9]+)").major')" || return 1
        new_db="$(DEPLOY_DIR="$stage" compose config --format json | jq -r --arg service "$service" '.services[$service].image // empty | capture(":(?<major>[0-9]+)").major')" || return 1
        if [[ "$old_db" != "$new_db" ]]; then
            [[ "$old_db" =~ ^[0-9]+$ && "$new_db" =~ ^[0-9]+$ ]] || fail 'Cannot identify database major versions.'
            (( new_db > old_db )) || fail 'Database major downgrades are not supported.'
            migration="$stage/migrations/$service-$old_db-$new_db.sh"
            [[ -f "$migration" && ! -L "$migration" ]] || fail "Release lacks the required migration: $service-$old_db-$new_db.sh"
            bash -n "$migration" || return 1
            migrations+=("$migration")
        fi
    done
    DEPLOY_DIR="$stage" compose config --quiet || return 1
    DEPLOY_DIR="$stage" compose pull || return 1
    backup_stack || return 1
    if [[ ${#migrations[@]} -gt 0 ]]; then
        compose stop --timeout 120 || return 1
        active="$(compose ps --status running -q)" || return 1
        [[ -z "$active" ]] || fail 'Containers must be stopped before database migration.'
    fi
    install -d -m 700 "$DEPLOY_DIR/private" || return 1
    printf '%s\n' "$(cat "$stage/VERSION")" > "$DEPLOY_DIR/private/update-in-progress" || return 1
    copy_release "$stage" "$DEPLOY_DIR" || return 1
    cp "$stage/compose.yml" "$DEPLOY_DIR/compose.yml" || return 1
    for migration in "${migrations[@]}"; do
        DEPLOY_DIR="$DEPLOY_DIR" DATA_DIR="$DATA_DIR" bash "$migration" || return 1
    done
    source "$DEPLOY_DIR/lib/deploy.sh"
    source "$DEPLOY_DIR/lib/hosts/fedora.sh"
    source "$DEPLOY_DIR/lib/fluxer.sh"
    if [[ "${QBITTORRENT_ENABLED:-no}" == yes ]]; then
        prepare_storage || return 1
    fi
    write_homepage || return 1
    write_routes || return 1
    configure_fedora_host || return 1
    fluxer_configure_public_voice || return 1
    if ! start_stack; then
        log 'Update did not become healthy. Do not downgrade images; restore the pre-update snapshot using docs/backup.md.'
        return 1
    fi
    install -m 644 "$DEPLOY_DIR/templates/systemd/"* /etc/systemd/system/ || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now den-boot-check.timer || return 1
    systemctl restart den-dns || return 1
    if [[ -f "$DEPLOY_DIR/private/ddns.env" ]]; then
        systemctl enable --now den-ddns.timer || return 1
    fi
    enable_update_timer || return 1
    rm "$DEPLOY_DIR/private/update-in-progress" || return 1
    log 'Release update completed. Monthly automatic maintenance also updates Fedora and enabled Fluxer.'
)

git_admin() {
    local username password
    read -r -p 'Git admin username: ' username
    [[ "$username" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,29}$ ]] || fail 'Use a simple username, up to 30 characters.'
    read -r -s -p 'Git admin password (at least 12 characters): ' password
    printf '\n'
    [[ ${#password} -ge 12 ]] || fail 'Password must be at least 12 characters.'
    compose exec -T -u git forgejo forgejo admin user create \
        --username "$username" --password "$password" --email "$EMAIL" --admin --must-change-password=false
    log 'Git administrator created; registrations remain closed. Use HTTPS and personal access tokens for Git.'
}