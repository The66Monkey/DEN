#!/usr/bin/env bash

install_packages() {
    install -d -m 755 /etc/yum.repos.d
    dnf install -y curl ca-certificates
    curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
        -o /etc/yum.repos.d/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
        docker-compose-plugin container-selinux firewalld restic wireguard-tools \
        dnsmasq iptables-nft jq openssl curl ca-certificates \
        policycoreutils-python-utils
    if [[ "$KEEPASS_ENABLED" == yes ]]; then
        dnf install -y python3-pykeepass
    fi
    systemctl enable --now firewalld
    systemctl enable --now docker
    docker compose version >/dev/null
}

configure_fedora_host() {
    local port
    for port in 80/tcp 443/tcp 51820/udp; do
        firewall-cmd --permanent --add-port="$port"
    done
    if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then
        firewall-cmd --permanent --add-port=7881/tcp
        firewall-cmd --permanent --add-port=7882/udp
    fi
    firewall-cmd --permanent --zone=trusted --add-interface=wg0
    firewall-cmd --reload

    if semanage fcontext -l -C | grep -Fq '/opt/den/private/dnsmasq\.conf'; then
        semanage fcontext -m -t dnsmasq_etc_t '/opt/den/private/dnsmasq\.conf'
    else
        semanage fcontext -a -t dnsmasq_etc_t '/opt/den/private/dnsmasq\.conf'
    fi
    restorecon /opt/den/private/dnsmasq.conf
}