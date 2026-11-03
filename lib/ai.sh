#!/usr/bin/env bash

ai_prepare() {
    [[ "${AI_ENABLED:-no}" == yes ]] || return 0
    local secrets="$DEPLOY_DIR/private/ai-webui.env" candidate key password
    install -d -m 700 "$DEPLOY_DIR/private" "$DATA_DIR/ai/webui" "$DATA_DIR/ai/ollama" || return 1
    [[ ! -L "$secrets" ]] || fail 'AI secret file cannot be a symlink.'
    if [[ ! -e "$secrets" ]]; then
        key="$(openssl rand -hex 32)" || return 1
        password="$(openssl rand -hex 24)" || return 1
        (
            umask 077
            printf 'WEBUI_SECRET_KEY=%s\nWEBUI_ADMIN_EMAIL=%s\nWEBUI_ADMIN_PASSWORD=%s\n' \
                "$key" "$EMAIL" "$password" > "$secrets"
        ) || return 1
    fi
    grep -Eq '^WEBUI_SECRET_KEY=[a-f0-9]{64}$' "$secrets" &&
        grep -Eq '^WEBUI_ADMIN_EMAIL=[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' "$secrets" &&
        grep -Eq '^WEBUI_ADMIN_PASSWORD=[a-f0-9]{48}$' "$secrets" ||
        fail 'AI secret file is incomplete; restore it from backup.'
    chmod 600 "$secrets" || return 1
    candidate="$(mktemp)" || return 1
    {
        printf 'HOME=%s/ai/ollama\nOLLAMA_MODELS=%s/ai/ollama/models\n' "$DATA_DIR" "$DATA_DIR"
        printf 'OLLAMA_HOST=127.0.0.1:11435\nOLLAMA_NO_CLOUD=1\nOLLAMA_CONTEXT_LENGTH=4096\n'
        printf 'OLLAMA_NUM_PARALLEL=1\nOLLAMA_MAX_LOADED_MODELS=1\nOLLAMA_KEEP_ALIVE=2m\n'
    } > "$candidate" || { rm -f "$candidate"; return 1; }
    install -m 600 "$candidate" "$DEPLOY_DIR/private/ai-ollama.env" || { rm -f "$candidate"; return 1; }
    rm -f "$candidate"
}

ai_install_runtime() {
    local runtime="$1" archive
    if [[ ! -f "$runtime/.verified" ]]; then
        install -d -m 755 "$runtime" || return 1
        archive="$(mktemp "${runtime%/*}/ollama-download.XXXXXX")" || return 1
        if ! curl -fLsS --retry 3 -o "$archive" https://github.com/ollama/ollama/releases/download/v0.40.13/ollama-linux-amd64.tar.zst ||
            ! printf '%s  %s\n' c9490e0f520be21271d969e6703f012268b1d39f8b70dd58854e5bfef7a75bb6 "$archive" | sha256sum --check --status ||
            ! tar --zstd -xf "$archive" -C "$runtime"; then
            rm -f "$archive"
            fail 'Could not download, verify or extract the pinned Ollama runtime.'
        fi
        rm -f "$archive"
        touch "$runtime/.verified" || return 1
    fi
}

ai_install() {
    [[ "${AI_ENABLED:-no}" == yes ]] || return 0
    local runtime=/opt/den-ai/ollama-0.40.13 group
    if ss -H -ltn '( sport = :11435 )' | grep -q . &&
        ! systemctl is-active --quiet den-ai-ollama.service; then
        fail 'Localhost port 11435 is already in use; explicitly migrate or stop the existing lab first.'
    fi
    if ! id den-ai >/dev/null 2>&1; then
        useradd --system --user-group --home-dir "$DATA_DIR/ai/ollama" --shell /usr/sbin/nologin den-ai || return 1
    fi
    for group in render video; do
        if getent group "$group" >/dev/null; then usermod -a -G "$group" den-ai || return 1; fi
    done
    ai_prepare || return 1
    chown -R den-ai:den-ai "$DATA_DIR/ai/ollama" || return 1
    ai_install_runtime "$runtime" || return 1
    install -m 644 "$DEPLOY_DIR/templates/systemd/den-ai-ollama.service" /etc/systemd/system/ || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now den-ai-ollama.service || return 1
    curl --fail --silent --show-error --retry 15 --retry-connrefused --retry-delay 2 \
        http://127.0.0.1:11435/api/version >/dev/null || return 1
    OLLAMA_HOST=127.0.0.1:11435 "$runtime/bin/ollama" pull "$AI_MODEL" || return 1
    ai_sync_vpn_dns || return 1
    log 'AI installed. Verify GPU use with sudo den ai-status; CPU fallback does not mean GPU acceleration is working.'
}

ai_sync_vpn_dns() {
    [[ "${AI_ENABLED:-no}" == yes ]] || return 0
    local file="$DEPLOY_DIR/private/dnsmasq.conf" record="host-record=ai.$DOMAIN,$LAN_IP"
    [[ -f "$file" ]] || fail 'VPN DNS configuration is missing.'
    if grep -Fxq "$record" "$file"; then return 0; fi
    if grep -Fq "host-record=ai.$DOMAIN," "$file"; then
        fail 'Conflicting AI VPN DNS record; review it before enabling AI.'
    fi
    printf '%s\n' "$record" >> "$file" || return 1
    dnsmasq --test --conf-file="$file" || return 1
    systemctl restart den-dns.service
}

ai_setup() {
    [[ "${AI_ENABLED:-no}" == yes ]] || fail 'Set AI_ENABLED=yes in the private DEN environment first.'
    ai_prepare || return 1
    compose config --quiet || return 1
    compose pull openwebui || return 1
    configure_nvidia_power || return 1
    ai_install || return 1
    write_homepage || return 1
    write_routes || return 1
    compose up -d --wait --wait-timeout 900 openwebui
}

ai_health_check() {
    [[ "${AI_ENABLED:-no}" == yes ]] || return 0
    systemctl is-active --quiet den-ai-ollama.service || fail 'DEN Ollama is down; run sudo den ai-status.'
    curl --fail --silent --show-error --max-time 10 http://127.0.0.1:11435/api/tags |
        jq -e --arg model "$AI_MODEL" 'any(.models[]; .name == $model or .name == ($model + ":latest"))' >/dev/null ||
        fail 'DEN AI model is unavailable; check the local Ollama service and model download.'
}

ai_start() {
    [[ "${AI_ENABLED:-no}" == yes ]] || return 0
    systemctl start den-ai-ollama.service
}

ai_stop() {
    [[ "${AI_ENABLED:-no}" == yes ]] || return 0
    systemctl stop den-ai-ollama.service
}

ai_status() {
    [[ "${AI_ENABLED:-no}" == yes ]] || fail 'AI is not enabled; see docs/ai.md.'
    systemctl status den-ai-ollama.service --no-pager || return 1
    OLLAMA_HOST=127.0.0.1:11435 /opt/den-ai/ollama-0.40.13/bin/ollama ps
}

configure_nvidia_power() {
    if [[ -z "${NVIDIA_POWER_LIMIT_W:-}" ]]; then
        if [[ -e /etc/den/nvidia-power.env ]]; then
            log 'Existing NVIDIA power policy retained; removing a config value never raises the hardware power limit.'
        fi
        return 0
    fi
    command -v nvidia-smi >/dev/null || fail 'A working NVIDIA driver is required for the requested power cap.'
    NVIDIA_GPU_ID="$NVIDIA_GPU_ID" NVIDIA_POWER_LIMIT_W="$NVIDIA_POWER_LIMIT_W" \
        bash "$DEPLOY_DIR/templates/nvidia-power-limit.sh" || return 1
    install -d -m 755 /etc/den || return 1
    (
        umask 077
        printf 'NVIDIA_GPU_ID=%s\nNVIDIA_POWER_LIMIT_W=%s\n' "$NVIDIA_GPU_ID" "$NVIDIA_POWER_LIMIT_W" > /etc/den/nvidia-power.env
    ) || return 1
    install -m 644 "$DEPLOY_DIR/templates/systemd/den-nvidia-power.service" \
        "$DEPLOY_DIR/templates/systemd/den-nvidia-power.timer" /etc/systemd/system/ || return 1
    systemctl daemon-reload || return 1
    systemctl start den-nvidia-power.service || return 1
    systemctl enable den-nvidia-power.service || return 1
    systemctl enable --now den-nvidia-power.timer
}
