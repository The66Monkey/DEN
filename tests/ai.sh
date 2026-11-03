#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
DATA_DIR="$TEMP/data"
read_settings "$ROOT/config/example.env"
[[ "$AI_ENABLED" == no && -z "$NVIDIA_POWER_LIMIT_W" ]]
ai_prepare
[[ ! -e "$DEPLOY_DIR/private/ai-webui.env" ]]
for invalid in 'AI_ENABLED=maybe' 'AI_MODEL=--bad' 'AI_MODEL=bad model' \
    'AI_REMOTE_OLLAMA_URL=http://192.168.1.2:11434' 'AI_REMOTE_OLLAMA_URL=http://127.0.0.1:65536' \
    'AI_REMOTE_OLLAMA_URL=http://127.0.0.1:11435' 'NVIDIA_POWER_LIMIT_W=-1' \
    'NVIDIA_POWER_LIMIT_W=125;id' 'NVIDIA_GPU_ID=0;id'; do
    if (printf -v "${invalid%%=*}" '%s' "${invalid#*=}"; validate_settings) 2>/dev/null; then
        fail "Accepted invalid AI setting: $invalid"
    fi
done
AI_ENABLED=yes
AI_REMOTE_OLLAMA_URL=http://127.0.0.1:11434
NVIDIA_POWER_LIMIT_W=125
validate_settings
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$DEPLOY_DIR"
read_settings "$DEPLOY_DIR/.env"
[[ "$AI_ENABLED" == yes && "$AI_MODEL" == llama3.2:3b && "$NVIDIA_POWER_LIMIT_W" == 125 ]]
ai_prepare
cp "$DEPLOY_DIR/private/ai-webui.env" "$TEMP/original-secrets"
[[ "$(stat -c %a "$DEPLOY_DIR/private/ai-webui.env")" == 600 ]]
grep -Eq '^WEBUI_SECRET_KEY=[a-f0-9]{64}$' "$TEMP/original-secrets"
grep -Eq '^WEBUI_ADMIN_PASSWORD=[a-f0-9]{48}$' "$TEMP/original-secrets"
grep -Fxq "WEBUI_ADMIN_EMAIL=$EMAIL" "$TEMP/original-secrets"
ai_prepare
cmp "$TEMP/original-secrets" "$DEPLOY_DIR/private/ai-webui.env"
grep -Fxq 'OLLAMA_HOST=127.0.0.1:11435' "$DEPLOY_DIR/private/ai-ollama.env"
grep -Fxq 'OLLAMA_NO_CLOUD=1' "$DEPLOY_DIR/private/ai-ollama.env"
write_routes
jq -e '.http.routers.ai.rule == "Host(`ai.home.example.net`)" and
    .http.routers.ai.middlewares == ["private","headers"] and
    .http.routers.ai.tls.certResolver == "home" and
    .http.services.ai.loadBalancer.servers[0].url == "http://172.30.44.1:28413"' "$DEPLOY_DIR/routes.json" >/dev/null
write_vpn_dns > "$DEPLOY_DIR/private/dnsmasq.conf"
grep -Fxq "host-record=ai.$DOMAIN,$LAN_IP" "$DEPLOY_DIR/private/dnsmasq.conf"
cp "$DEPLOY_DIR/private/dnsmasq.conf" "$TEMP/dns"
ai_sync_vpn_dns
cmp "$TEMP/dns" "$DEPLOY_DIR/private/dnsmasq.conf"
grep -v "^host-record=ai\\." "$TEMP/dns" > "$DEPLOY_DIR/private/dnsmasq.conf"
printf 'host-record=other.example.net,192.168.1.20\n' >> "$DEPLOY_DIR/private/dnsmasq.conf"
dnsmasq() { printf 'dnsmasq %s\n' "$*" >> "$TEMP/calls"; }
systemctl() { printf 'systemctl %s\n' "$*" >> "$TEMP/calls"; }
ai_sync_vpn_dns
grep -Fxq 'host-record=other.example.net,192.168.1.20' "$DEPLOY_DIR/private/dnsmasq.conf"
grep -Fxq 'systemctl restart den-dns.service' "$TEMP/calls"
install -d "$DEPLOY_DIR/home" "$DEPLOY_DIR/docs/images" "$DEPLOY_DIR/templates"
cp "$ROOT/docs/images/mascot.png" "$DEPLOY_DIR/docs/images/"
cp "$ROOT/templates/home.html" "$DEPLOY_DIR/templates/"
write_homepage
grep -Fq "https://ai.$DOMAIN/" "$DEPLOY_DIR/home/index.html"
cp "$ROOT/templates/compose.yml" "$DEPLOY_DIR/compose.yml"
cp "$ROOT/templates/compose.ai.yml" "$ROOT/templates/compose.dns.yml" "$DEPLOY_DIR/templates/"
if [[ -n "${COMPOSE_BIN:-}" ]]; then
    "$COMPOSE_BIN" --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/compose.yml" \
        -f "$DEPLOY_DIR/templates/compose.dns.yml" -f "$DEPLOY_DIR/templates/compose.ai.yml" \
        config --format json > "$TEMP/compose.json"
else
    ACME_CHALLENGE=dns-desec compose config --format json > "$TEMP/compose.json"
fi
jq -e '.services.openwebui as $s |
    $s.network_mode == "host" and $s.ports == null and $s.environment.HOST == "172.30.44.1" and
    $s.environment.PORT == "28413" and $s.environment.WEBUI_AUTH == "true" and
    $s.environment.ENABLE_SIGNUP == "false" and $s.environment.ENABLE_DIRECT_CONNECTIONS == "false" and
    $s.environment.OLLAMA_BASE_URLS == "http://127.0.0.1:11435;http://127.0.0.1:11434" and
    $s.environment.WEBUI_ADMIN_EMAIL == "you@example.net" and
    ($s.environment.WEBUI_ADMIN_PASSWORD | test("^[a-f0-9]{48}$")) and
    ($s.image | endswith("@sha256:03443b8de6b617da9d900edd09b4bf1cb0ddbfdcba6afb42c548336a0b821ded")) and
    ($s.volumes[0].source == "/srv/den/ai/webui") and $s.healthcheck != null and
    .services.traefik.environment.DESEC_TOKEN_FILE == "/run/secrets/desec-token" and
    (.services.traefik.command | index("--certificatesresolvers.home.acme.dnschallenge.propagation.delaybeforechecks=60s") != null)
    ' "$TEMP/compose.json" >/dev/null
sed -i 's|^AI_REMOTE_OLLAMA_URL=.*|AI_REMOTE_OLLAMA_URL=|' "$DEPLOY_DIR/.env"
if [[ -n "${COMPOSE_BIN:-}" ]]; then
    "$COMPOSE_BIN" --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/templates/compose.ai.yml" config --format json > "$TEMP/local-only.json"
else
    compose config --format json > "$TEMP/local-only.json"
fi
jq -e '.services.openwebui.environment.OLLAMA_BASE_URLS == "http://127.0.0.1:11435"' "$TEMP/local-only.json" >/dev/null
AI_ENABLED=no
write_routes
jq -e '.http.routers.ai == null and .http.services.ai == null' "$DEPLOY_DIR/routes.json" >/dev/null
write_homepage
! grep -Fq "https://ai.$DOMAIN/" "$DEPLOY_DIR/home/index.html"

mkdir "$TEMP/bin"
cat > "$TEMP/bin/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *power.min_limit* ]]; then
    printf '100.00, 163.46, %s\n' "$(cat "$POWER_STATE")"
elif [[ "$*" == *--power-limit=* ]]; then
    [[ "${POWER_FAIL:-no}" != yes ]] || exit 1
    printf '%s\n' "${*: -1}" | cut -d= -f2 > "$POWER_STATE"
    printf 'set\n' >> "$POWER_CALLS"
else
    cat "$POWER_STATE"
fi
EOF
chmod +x "$TEMP/bin/nvidia-smi"
export POWER_STATE="$TEMP/power" POWER_CALLS="$TEMP/power-calls"
export NVIDIA_GPU_ID=0 NVIDIA_POWER_LIMIT_W=125
printf '148.60\n' > "$POWER_STATE"
PATH="$TEMP/bin:$PATH" bash "$ROOT/templates/nvidia-power-limit.sh"
[[ "$(cat "$POWER_STATE")" == 125 ]]
PATH="$TEMP/bin:$PATH" bash "$ROOT/templates/nvidia-power-limit.sh"
[[ "$(wc -l < "$POWER_CALLS")" == 1 ]]
printf '148.60\n' > "$POWER_STATE"
PATH="$TEMP/bin:$PATH" bash "$ROOT/templates/nvidia-power-limit.sh"
[[ "$(cat "$POWER_STATE")" == 125 && "$(wc -l < "$POWER_CALLS")" == 2 ]]
printf '148.60\n' > "$POWER_STATE"
if POWER_FAIL=yes PATH="$TEMP/bin:$PATH" bash "$ROOT/templates/nvidia-power-limit.sh" 2>/dev/null; then
    fail 'Power-limit application failure returned success.'
fi
if NVIDIA_POWER_LIMIT_W=99 PATH="$TEMP/bin:$PATH" bash "$ROOT/templates/nvidia-power-limit.sh" 2>/dev/null; then
    fail 'Out-of-range power limit accepted.'
fi
curl() { [[ "${FAIL_DOWNLOAD:-no}" != yes ]]; }
sha256sum() { cat >/dev/null; [[ "${FAIL_CHECKSUM:-no}" != yes ]]; }
tar() { [[ "${FAIL_EXTRACT:-no}" != yes ]]; }
for failure in FAIL_DOWNLOAD FAIL_CHECKSUM FAIL_EXTRACT; do
    if (printf -v "$failure" yes; ai_install_runtime "$TEMP/$failure") 2>/dev/null; then
        fail "Failed runtime installation returned success: $failure"
    fi
    [[ ! -e "$TEMP/$failure/.verified" ]]
done
ai_install_runtime "$TEMP/runtime"
[[ -f "$TEMP/runtime/.verified" ]]
FAIL_DOWNLOAD=yes ai_install_runtime "$TEMP/runtime"
[[ -z "$(find "$TEMP" -maxdepth 1 -name 'ollama-download.*' -print -quit)" ]]
printf 'AI settings, persistent secrets, private routing/DNS, Compose and NVIDIA cap checks passed.\n'
