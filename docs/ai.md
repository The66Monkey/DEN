# Optional private AI

Set `AI_ENABLED=yes` to install Open WebUI at `https://ai.DOMAIN` and native
Ollama on DEN. Chats, accounts and uploads stay in `/srv/den/ai/webui`;
DEN model weights stay in `/srv/den/ai/ollama`. No cloud inference is enabled.
The feature is off by default. Allow several GB for the runtime, a model,
WebUI and its document/embedding dependencies, plus backups.

## Installation

Before a new installation, set these in your private installer settings:

```text
AI_ENABLED=yes
AI_MODEL=llama3.2:3b
AI_REMOTE_OLLAMA_URL=
```

For an existing DEN, first update to a release supporting these settings,
back up, then edit `/opt/den/.env` and run `sudo den ai-setup`.
This provisions AI, adds the homepage/HTTPS route and exact VPN DNS record,
without restarting other apps. It does not import an existing standalone lab.
Do not run it if another server already uses localhost port 11435.
Updates and recovery use the saved AI configuration, stable WebUI secret,
and model selection; no post-update route reapply script is needed.

Open WebUI uses a pinned image. Native Ollama uses a pinned, SHA-256-verified
x86_64 Linux runtime under `/opt/den-ai`. It runs as a dedicated `den-ai` user,
not root. No GPU drivers, global SELinux switches or container GPU permissions
are changed. CPU fallback is possible; it is **not** proof that GPU inference
works. AMD Vulkan needs a working host Vulkan driver; AMD ROCm libraries are
not installed by this feature.

DEN creates the initial administrator using `EMAIL` and a random password in
`/opt/den/private/ai-webui.env`. Retrieve that file privately over SSH, sign in,
and change the password in WebUI. Signups are disabled from first startup.
The generated credentials only provision a fresh database; they do not reset
an existing account. Keep the secret file for stable sessions across recreation.
`ENABLE_PERSISTENT_CONFIG=false` makes deployment-controlled connection/access
settings authoritative; change them in DEN configuration, not just the UI.
Add further users from the administrator UI.

## Private hostname and HTTPS

DEN's `ai.` route uses the same LAN/VPN allowlist as other private apps, even
when public Fluxer is enabled. Ollama listens only on `127.0.0.1:11435`.
WebUI uses host networking to reach localhost Ollama/SSH endpoints, but its
listener binds **only the DEN Docker bridge gateway**, `172.30.44.1:28413`;
Traefik is its browser-facing entry point. Host networking is intentional:
do not change WebUI's bind address to `0.0.0.0` or publish its backend port.
Other trusted containers can reach the bridge listener, but authentication is
still required. Do not forward WebUI or Ollama ports from the router.

With `ACME_CHALLENGE=dns-desec`, no public AI A/AAAA record is required or
created by DDNS. Allow the DNS token to manage `_acme-challenge.ai` TXT records.
Certificates publish the hostname in public certificate-transparency logs.
DNS challenges wait 60 seconds and check both configured recursive resolvers;
issuance may still take minutes while DNS caches converge. Do not disable TLS
verification or delete existing certificates to fix a propagation delay.
DEN always combines DNS, AI and enabled torrent Compose overrides, preserving
the DNS-token file mount and its permissions when recreating Traefik.
With HTTP certificates, `ai.` needs a public A record pointing at DEN's existing
public HTTP endpoint for validation; manage that optional record yourself.
The HTTPS app remains allowlisted.

The DEN WireGuard DNS record is generated automatically. For LAN devices without
VPN, add an exact `ai.YOUR-DOMAIN -> DEN-LAN-IP` rewrite to your existing resolver
(for example AdGuard). Do not replace unrelated DNS records or wildcard your
whole domain. No BASM configuration or DNS credentials belong in this repository.

## Models and GPU memory

The default 3B model is a modest chat model, not a replacement for a large coder.
DEN defaults to a 4096-token context, one loaded model and one inference request
at a time. Ollama unloads after two idle minutes; opening or closing the website
does not directly load/unload GPU memory. Larger models, contexts, document
processing and concurrent media work need more RAM/VRAM.

```bash
sudo den ai-status
sudo journalctl -u den-ai-ollama.service -n 50 --no-pager
OLLAMA_HOST=127.0.0.1:11435 /opt/den-ai/ollama-0.40.13/bin/ollama ps
OLLAMA_HOST=127.0.0.1:11435 /opt/den-ai/ollama-0.40.13/bin/ollama stop llama3.2:3b
```

Verify **actual generation**, then inspect `ollama ps` for GPU use. Older NVIDIA
cards need a compatible legacy driver and CUDA backend; the pinned runtime
includes CUDA 12 as well as CUDA 13. Do not replace a working driver merely
because CUDA 13 skips an old GPU. A GTX 970 with a suitable 580-series driver
was verified with the 3B model entirely on GPU; other hardware must be tested.
GPU inference can contend with Jellyfin and other GPU workloads.

## Optional workstation GPU

Keep a second Ollama on your workstation bound to localhost. Set:

```text
AI_REMOTE_OLLAMA_URL=http://127.0.0.1:11434
```

From the workstation, forward a private listener back to DEN using existing SSH
access (replace the login/IP). This never exposes the workstation API to LAN:

```bash
ssh -NT -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -R 127.0.0.1:11434:127.0.0.1:11434 YOUR-USER@DEN-LAN-IP
```

On Fedora, SELinux may block SSH binding that port. Only after approving the
change, inspect `semanage port -l` and, if unassigned, label **only** that port:
`sudo semanage port -a -t ssh_port_t -p tcp 11434`. Keep SELinux enforcing;
do not enable broad booleans. Keep SSH gateway forwarding disabled. The
installer does not alter SSH policy, copy private keys or label tunnel ports.
For automatic reconnect, place the command in a workstation systemd user unit
with `Restart=always`, `RestartSec=10`, and enable it for `default.target`.
It starts at login; starting before login needs a separately approved lingering
change. No workstation model weights are stored on DEN.

Rerun `sudo den ai-setup` after changing the endpoint. Both providers are
aggregated into WebUI's model picker. **Selection is manual**, not automatic
substitution: choose DEN's model when the workstation is offline. The browser
device does not determine which GPU is used. Workstation connectivity is not
a DEN health-check prerequisite; DEN's own model is.

For imported GGUFs, use the exact Ollama model tag. A model can generate text
but reject WebUI's native tools if its embedded chat template lacks tool support.
Use the architecture's supported built-in Ollama `RENDERER`/`PARSER` where
appropriate (for compatible Qwen3.5-family GGUFs: `qwen3.5`, with
`TEMPLATE """{{ .Prompt }}"""`), and verify greeting and real tool calls.
Do not merely claim tool capability for an incompatible model.
Vision projectors are separate; text-only imports do not automatically add vision.
Continue can connect directly to workstation Ollama, independently of WebUI.
Autocomplete requests can reload an unloaded model: disable it while gaming.

## Backups, stopping and migration

`sudo den stop` stops WebUI and native DEN Ollama; `sudo den start` starts them.
Backups stop WebUI and the running local model server for a consistent snapshot,
then restore their prior running state. AI files and local model weights are
included in the existing `/srv/den` backup; allow for their size. Recovery
restores data/secrets, recreates the native user/runtime/service, and regenerates
the private route. Workstation models remain that machine's responsibility.

An existing lab is not auto-adopted: preserve its admin database, uploads and
secret, stop conflicting listeners, then plan an explicit backup-based migration
to `/srv/den/ai`. Never create a fresh database over the old lab or delete its
volumes to resolve port conflicts. Until migrated, leave `AI_ENABLED=no` on the
production deployment; the standalone lab keeps working independently.
