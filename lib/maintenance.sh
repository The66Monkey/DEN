#!/usr/bin/env bash

copy_release() {
    local source_dir="$1" destination="$2" item
    install -d -m 700 "$destination" || return 1
    for item in bin lib templates docs config; do
        cp -a "$source_dir/$item" "$destination/" || return 1
    done
    for item in VERSION README.md install.sh update.sh recover.sh; do
        install -m 600 "$source_dir/$item" "$destination/$item" || return 1
    done
    chmod 755 "$destination/bin/den"
}

health_check() {
    local expected actual snapshots newest now used
    expected="$(compose config --services | wc -l)"
    actual="$(compose ps --all --format json | jq -s 'flatten | map(select(.State == "running" and .Health == "healthy")) | length')"
    [[ "$actual" == "$expected" ]] || fail "Only $actual/$expected containers are healthy. Run sudo den status."
    systemctl is-active --quiet wg-quick@wg0 den-dns || fail 'WireGuard or VPN DNS is down.'
    ensure_backup_mount
    snapshots="$(restic_cmd snapshots --host den --tag den-v1 --json)"
    newest="$(jq -r 'sort_by(.time) | last | .time // empty' <<< "$snapshots")"
    [[ -n "$newest" ]] || fail 'No successful DEN backup exists.'
    newest="$(date -d "$newest" +%s)"; now="$(date +%s)"
    (( now - newest < 129600 )) || fail 'Last backup is more than 36 hours old.'
    used="$(df --output=pcent "$DATA_DIR" | tail -1 | tr -dc '0-9')"
    (( used < 90 )) || fail 'Data filesystem is at least 90% full.'
    install -d -m 755 /etc/motd.d
    printf 'DEN: services healthy; recent backup present.\n' > /etc/motd.d/den
    log 'Services, VPN, backup age and free space look healthy.'
}

update_release() (
    local source_dir="$1" stage old_major new_major
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
    DEPLOY_DIR="$stage" compose config --quiet || return 1
    DEPLOY_DIR="$stage" compose pull || return 1
    backup_stack || return 1
    copy_release "$stage" "$DEPLOY_DIR" || return 1
    cp "$stage/compose.yml" "$DEPLOY_DIR/compose.yml" || return 1
    source "$DEPLOY_DIR/lib/deploy.sh"
    write_routes || return 1
    if ! start_stack; then
        log 'Update did not become healthy. Do not downgrade images; restore the pre-update snapshot using docs/backup.md.'
        return 1
    fi
    install -m 644 "$DEPLOY_DIR/templates/systemd/"* /etc/systemd/system/
    systemctl daemon-reload
    systemctl restart den-dns
    log 'Update completed. Host packages are updated separately with apt; no unattended container upgrades.'
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