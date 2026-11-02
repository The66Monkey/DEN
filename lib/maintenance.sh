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

enable_update_timer() {
    local state status=0
    state="$(systemctl is-enabled den-update.timer)" || status=$?
    case "$state" in
        masked|masked-runtime) log 'Monthly updates are explicitly masked; preserving the opt-out.' ;;
        enabled|disabled) systemctl enable --now den-update.timer || return 1 ;;
        *) fail "Cannot determine update timer state ($state, exit $status)." ;;
    esac
}

health_check() {
    local expected actual snapshots newest now used
    ensure_media_storage
    expected="$(compose config --services | wc -l)"
    actual="$(compose ps --all --format json | jq -s 'flatten | map(select(.State == "running" and .Health == "healthy")) | length')"
    [[ "$actual" == "$expected" ]] || fail "Only $actual/$expected containers are healthy. Run sudo den status."
    systemctl is-active --quiet wg-quick@wg0 den-dns || fail 'WireGuard or VPN DNS is down.'
    systemctl is-active --quiet den-firewall || fail 'DEN network guard is down.'
    nft list table inet den_guard >/dev/null || fail 'DEN network guard rules are missing.'
    fluxer_health_check
    ensure_backup_mount
    snapshots="$(restic_cmd snapshots --host den --tag den-v1 --json)"
    newest="$(jq -r 'sort_by(.time) | last | .time // empty' <<< "$snapshots")"
    [[ -n "$newest" ]] || fail 'No successful DEN backup exists.'
    newest="$(date -d "$newest" +%s)"; now="$(date +%s)"
    (( now - newest < 129600 )) || fail 'Last backup is more than 36 hours old.'
    used="$(df --output=pcent "$DATA_DIR" | tail -1 | tr -dc '0-9')"
    (( used < 90 )) || fail 'Data filesystem is at least 90% full.'
    if [[ -n "${MEDIA_MOUNT:-}" ]]; then
        used="$(df --output=pcent "$MEDIA_MOUNT" | tail -1 | tr -dc '0-9')"
        (( used < 90 )) || fail 'Secondary storage filesystem is at least 90% full.'
    fi
    install -d -m 755 /etc/motd.d
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
    cp "$stage/templates/compose.yml" "$stage/compose.yml" || return 1
    cp "$DEPLOY_DIR/routes.json" "$stage/routes.json" || return 1
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
    if [[ "${QBITTORRENT_ENABLED:-no}" == yes ]]; then
        prepare_storage || return 1
    fi
    write_routes || return 1
    configure_fedora_host || return 1
    if ! start_stack; then
        log 'Update did not become healthy. Do not downgrade images; restore the pre-update snapshot using docs/backup.md.'
        return 1
    fi
    install -m 644 "$DEPLOY_DIR/templates/systemd/"* /etc/systemd/system/ || return 1
    systemctl daemon-reload || return 1
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