case $- in
*i*)
    server_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
    if [ -z "$server_ip" ]; then
        server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    [ -n "$server_ip" ] || server_ip=unavailable

    service_status="$(systemctl is-active den.service 2>/dev/null || true)"
    [ -n "$service_status" ] || service_status=unknown

    printf '\n=== DEN ===\nHost: %s  |  IPv4: %s\nService: %s\nTip: sudo den status\n\n' \
        "$(hostname)" "$server_ip" "$service_status"
    ;;
esac
