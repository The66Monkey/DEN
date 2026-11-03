# Independent DNS and a shared HTTPS edge

This is an **optional administrator-managed topology**, not a dependency on
BASM and not a default installer change. On one public IPv4, a single reverse
proxy must own forwarded TCP 80/443 and route exact hostnames to the right
server. DNS chooses an address; it does not proxy web traffic.

Recommended layout when a business VM shares the home host:

```text
LAN clients -> DEN AdGuard (DNS only)
Internet -> router TCP 80/443 -> DEN infrastructure edge
                                |-> DEN apps / public chat
                                `-> verified HTTPS -> business VM
DEN VPN clients -> DEN VPN DNS -> private LAN endpoints
```

AdGuard and the edge run in the separate `den-infrastructure` Compose project.
They remain up during DEN application backups/stops and business-VM maintenance.
Business applications still require their VM; household DNS and DEN chat do not.
The host remains a single point of failure; this is not high availability.
DEN's existing VPN DNS stays independent.

## Preparation and explicit migration

Use DNS-challenge certificates (`ACME_CHALLENGE=dns-desec`). Review and back up
the current router, DNS, routes, certificates and private deployment settings.
Never publish API tokens, ACME accounts/private keys or copied AdGuard settings.
Check that `172.30.45.0/24`, LAN TCP/UDP 53 and loopback TCP 3080 are free.
The existing `den_home` network must exist before starting infrastructure.

1. Copy `templates/compose.infrastructure.yml` to
   `/opt/den/private/infrastructure/compose.yml`. Save a private `.env` beside
   it with `LAN_IP` and `EMAIL`; root owns both files/directories (`0600`/`0700`).
   Standard paths are `/opt/den` and `/srv/den`; custom roots can set
   `DEN_DEPLOY_DIR` and `DEN_DATA_DIR`.
2. Explicitly initialize or migrate AdGuard into
   `/srv/den/infrastructure/adguard/{conf,work}`. For migration, briefly stop
   the old AdGuard while copying, then restart it as a fallback. Preserve its
   administrator password hash, filters, client settings and upstream resolvers.
   The template expects AdGuard's internal UI on port 3000; adjust migrated
   `http.address` if needed. Restrict DNS clients to your LAN/VPN and the DNS
   container's bridge subnet. Never expose port 53 or the management UI publicly.
3. Keep `/srv/den/traefik/acme.json` and the private deSEC token in their existing
   locations. The edge retains `172.30.44.2`, which Nextcloud already trusts.
   It also provides a `business` resolver using TLS-ALPN-01, stored separately
   in `business-acme.json`. Existing business certificates can be privately
   migrated into that resolver's ACME store, preserving the account and keys.
   Only one running proxy may write a given ACME file; never share one writable
   file between proxies.
   The business backend also needs independent certificate renewal: switch its
   proxy to DNS-01 (BASM supports a private `data/traefik/desec-token` file).
   TLS-ALPN-01 on a backend cannot renew through a TLS-terminating outer edge.
   On BASM, save DEN's exact LAN IPv4 in `config/traefik-edge-ip` to preserve
   forwarded client addresses without trusting arbitrary senders.
4. Put administrator-owned extra routes in
   `/opt/den/private/routes-custom.json`. Only HTTP `routers`, `services`,
   `middlewares` and `serversTransports` can be added. Managed names cannot be
   overwritten. Use exact `Host(...)` rules and verified HTTPS to VM backends;
   specify `serversTransports.<name>.serverName` when connecting by IP.
   Do not add a blanket domain wildcard or a LAN-source bypass for private apps.
   `write_routes` merges this file on updates/recovery without replacing the
   bind-mounted output inode. Invalid custom entries fail without changing
   the previously generated routes.
5. Under the DEN operation lock, stop/remove **only** the old DEN `traefik`
   container, create `/opt/den/private/external-edge`, and use the matching
   release's `lib/deploy.sh` and `templates/compose.external-edge.yml`.
   The marker removes the embedded edge from normal app lifecycle commands.
   Never start both proxies on ports 80/443 or address `172.30.44.2`.
6. Install `templates/systemd/den-infrastructure.service` and enable it with
   `systemctl enable --now den-infrastructure`. This is separate from
   `den.service`. Apply DEN's reviewed firewall policy: external edge enables
   public TCP 80/443, DNS is allowed only from the LAN, and existing private app
   allowlists stay in effect. No router changes to SSH/admin ports are needed.

AdGuard administration stays loopback-only:

```sh
ssh -N -L 3080:127.0.0.1:3080 USER@DEN-LAN-IP
# Open http://127.0.0.1:3080 and use the existing AdGuard account.
```

## Verify before changing the router

- Query DEN directly over both UDP and TCP DNS. Check enabled DEN names,
  business names, an ordinary external name and `vpn.DOMAIN`.
- Test every public hostname against DEN using
  `curl --resolve HOST:443:DEN-LAN-IP https://HOST/`; do not disable certificate
  verification. Verify an existing certificate before moving traffic.
- Test private apps from outside the LAN/VPN after cutover: they must remain
  denied. Seeing a LAN response does not test the public access boundary.
- Check the infrastructure Compose state, unit enablement and proxy logs.
- Leave old DNS/proxy listeners and private rollback copies available until
  clients on mobile data and the LAN confirm the cutover.

Change router TCP **80/443** forwarding to DEN. Leave BASM SMTP and RustDesk
forwarding alone. DEN WireGuard and Fluxer voice ports retain their own direct
DEN forwards. Change LAN DHCP DNS to DEN, remove competing secondary DNS and
renew client leases. Check IPv6 DNS advertisements and browser Secure DNS too.

**deSEC:** normally no A-record edits are needed: the public IPv4 did not
change. Existing root/business/chat records still point to the router.
Keep `vpn.DOMAIN` public in every resolver; no AI public record is needed.
Leave MX/TXT mail records unchanged. Keep one DDNS owner per hostname.
LAN rewrites should point public web hostnames to the edge, while private DEN
names point directly to DEN. A separate public IP is not required.

## Operations, backups and recovery

```sh
sudo systemctl status den-infrastructure
sudo docker compose --project-name den-infrastructure \
  --project-directory /opt/den/private/infrastructure \
  --env-file /opt/den/private/infrastructure/.env \
  -f /opt/den/private/infrastructure/compose.yml ps
```

The unit starts the containers without waiting on health and retries on failure;
Docker's `unless-stopped` policy keeps them running. The DNS container's own
healthcheck only queries a locally answered name, so a slow upstream at boot
cannot mark local DNS unhealthy. Clients should keep DEN as the only LAN DNS
server: a second public resolver would bypass private names and filtering.

DEN health checks include infrastructure when the marker exists. Its regular
encrypted snapshot includes the infrastructure Compose/env files, custom routes,
AdGuard configuration and both certificate stores. AdGuard's live work directory
(query logs, statistics and downloadable filter cache) is intentionally excluded;
filters rebuild on recovery. Edge and DNS are not paused for app snapshots.

Infrastructure images are pinned and **updated separately**, not implicitly by
application updates. Review/copy a newer infrastructure template, validate Compose
and apply it during a maintenance window. App updates retain the marker and
custom routes. Recovery restores `private/` and `/srv/den`, then requires the
network and the infrastructure unit to be recreated/enabled explicitly before
clients depend on it. Do not initialize a fresh AdGuard over a migrated config.

After router/client verification, stop and disable restart for the old DNS
container, remove any temporary reverse chat route on the business proxy, and
retain the business proxy as a LAN backend. Review legacy VPN DNS dependencies
before retiring old DNS: an old VPN profile may still explicitly use it.
Also check host OS resolver settings and persistent DHCP/network configuration;
the business VM itself may still point at its retired DNS listener.
If an old VPN uses its own CoreDNS forwarder, point that forwarder at DEN and
restart only its DNS service where supported; existing peer keys/profiles need
not change. Remove the old DNS container's `depends_on` relationship and place
that service behind a disabled legacy profile with `restart: "no"` so VM
maintenance cannot silently bring it back.
Do not delete VM data, old VPN keys or rollback archives as part of this cutover.
To roll back, restore router forwarding and DHCP DNS to their previous targets
and restart old DNS before stopping the new infrastructure.
