#!/usr/bin/env bash

install_packages() {
    install -d -m 755 /etc/yum.repos.d
    dnf install -y curl ca-certificates
    curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
        -o /etc/yum.repos.d/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
        docker-compose-plugin container-selinux firewalld restic wireguard-tools qrencode \
        dnsmasq iptables-nft nftables jq openssl curl ca-certificates \
        policycoreutils-python-utils git dnf5-plugins
    if [[ "$KEEPASS_ENABLED" == yes ]]; then
        dnf install -y python3-pykeepass
    fi
    systemctl enable --now firewalld
    systemctl enable --now docker
    docker compose version >/dev/null
}

write_network_guard() {
    cat <<EOF
add table inet den_guard
flush table inet den_guard
table inet den_guard {
    chain ingress {
        type filter hook prerouting priority -110; policy accept;
        iifname "lo" return
        iifname "docker0" return
        iifname "br-*" return
        ct state invalid counter drop
        iifname "wg0" goto vpn
        ct state established,related return
        ip saddr $LAN_CIDR return
        udp sport 67 udp dport 68 return
        ip6 saddr fe80::/10 udp sport 547 udp dport 546 return
        icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem } return
        ip6 hoplimit 255 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } return
        fib daddr type local udp dport $WIREGUARD_PORT return
EOF
    if [[ "${ACME_CHALLENGE:-http}" == http ]]; then
        printf '        ip daddr %s tcp dport 80 return\n' "$LAN_IP"
    fi
    cat <<EOF
        counter drop
    }
    chain vpn {
        meta nfproto ipv6 counter drop
        ip saddr != 10.44.0.0/24 counter drop
        ct state established,related return
        fib daddr type local tcp dport { 22, 53, 80, 443, 9090$(if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then printf ', 7881'; fi) } return
        fib daddr type local udp dport { 53$(if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then printf ', 7882'; fi) } return
        fib daddr type local ip protocol icmp return
        fib daddr type local counter drop
        ip daddr $LAN_CIDR return
        counter drop
    }
}
EOF
}

configure_network_guard() (
    set -euo pipefail
    local candidate
    candidate="$(mktemp)" || exit 1
    trap 'rm -f "$candidate"' EXIT
    write_network_guard > "$candidate" || exit 1
    nft --check --file "$candidate" || exit 1
    install -d -m 755 /etc/den /etc/systemd/system/docker.service.d || exit 1
    install -m 600 "$candidate" /etc/den/network.nft || exit 1
    install -m 644 "$DEPLOY_DIR/templates/systemd/den-firewall.service" /etc/systemd/system/ || exit 1
    cat > /etc/systemd/system/docker.service.d/den-firewall.conf <<'EOF' || exit 1
[Unit]
Requires=den-firewall.service
After=den-firewall.service
EOF
    systemctl daemon-reload || exit 1
    systemctl enable den-firewall.service || exit 1
    systemctl reload-or-restart den-firewall.service || exit 1
)

configure_fedora_host() {
    local port
    for port in 80/tcp 443/tcp "$WIREGUARD_PORT/udp"; do
        firewall-cmd --permanent --add-port="$port" || return 1
    done
    if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then
        firewall-cmd --permanent --add-port=7881/tcp || return 1
        firewall-cmd --permanent --add-port=7882/udp || return 1
    fi
    firewall-cmd --permanent --add-service=cockpit || return 1
    if ! firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -Fxq den-vpn; then
        firewall-cmd --permanent --new-zone=den-vpn || return 1
    fi
    firewall-cmd --permanent --zone=den-vpn --set-target=ACCEPT || return 1
    firewall-cmd --permanent --zone=den-vpn --change-interface=wg0 || return 1
    configure_network_guard || return 1
    firewall-cmd --reload || return 1

    if semanage fcontext -l -C | grep -Fq '/opt/den/private/dnsmasq\.conf'; then
        semanage fcontext -m -t dnsmasq_etc_t '/opt/den/private/dnsmasq\.conf' || return 1
    else
        semanage fcontext -a -t dnsmasq_etc_t '/opt/den/private/dnsmasq\.conf' || return 1
    fi
    restorecon /opt/den/private/dnsmasq.conf
}