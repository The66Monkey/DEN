#!/usr/bin/env bash
set -euo pipefail
source /opt/den/lib/core.sh
read_settings /opt/den/.env

verify_boot() {
    local attempt state response
    state="$(systemctl is-enabled den.service)" || [[ "$state" == disabled || "$state" == masked ]] || return 1
    if [[ "$state" == disabled || "$state" == masked ]]; then
        printf 'DEN: post-boot verification skipped; den.service is explicitly %s.\n' "$state"
        return 0
    fi
    for attempt in 1 2 3; do
        state="$(systemctl show den.service -p ActiveState --value)" || return 1
        case "$state" in
            failed)
                printf 'DEN: boot check attempt %s: starting unavailable DEN service.\n' "$attempt" >&2
                if ! systemctl start den.service; then
                    printf 'DEN: DEN startup failed; inspect journalctl -u den.service -b.\n' >&2
                fi
                ;;
            active|activating) ;;
            inactive)
                printf 'DEN: service is inactive; respecting a possible manual stop (no restart).\n' >&2
                return 1
                ;;
            *) printf 'DEN: unexpected DEN service state: %s\n' "$state" >&2; return 1 ;;
        esac
        if systemctl is-active --quiet den.service &&
            /usr/local/bin/den check &&
            { [[ ! -f /etc/den-plus/nvidia-power.env ]] ||
                nvidia-smi --query-gpu=name --format=csv,noheader >/dev/null; } &&
            response="$(curl --noproxy '*' --fail --silent --show-error --connect-timeout 5 --max-time 15 \
                --resolve "home.$DOMAIN:443:$LAN_IP" -w '%{http_code}' -o /dev/null "https://home.$DOMAIN/")" &&
            [[ "$response" == 200 ]]; then
            install -d -m 700 /srv/den/cache
            printf 'boot_id=%s\nverified_at=%s\n' "$(cat /proc/sys/kernel/random/boot_id)" \
                "$(date -u +%FT%TZ)" > /srv/den/cache/boot-verified
            printf 'DEN: post-boot services, GPU/backup/storage checks and homepage HTTPS passed.\n'
            return 0
        fi
        printf 'DEN: post-boot verification attempt %s/3 failed; no healthy services will be restarted.\n' "$attempt" >&2
        if [[ "$attempt" != 3 ]]; then sleep 30; fi
    done
    printf 'DEN: post-boot verification failed; run sudo den check and inspect den-boot-check.service.\n' >&2
    return 1
}

verify_boot
