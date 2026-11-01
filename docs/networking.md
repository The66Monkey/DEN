# Router and DNS

DEN chooses a single model: publicly valid HTTPS names, with application access restricted to your LAN and WireGuard. It does not offer alternative TLS providers, tunnels, or certificate modes.

## One-Time Preparation

1. Note the server's LAN IPv4 shown by Fedora Server (or run `hostname -I`). Reserve it for the server's network adapter in your router's DHCP settings, for example `192.168.1.10`. This becomes `LAN_IP`; put the home subnet, for example `192.168.1.0/24`, in `LAN_CIDR`.
2. Use [deSEC](https://desec.io) for public DNS: add your domain and, for your own registered domain, configure its nameservers at your registrar as deSEC instructs. Create public DNS **A** records for your domain and `media`, `photos`, `files`, and `git` beneath it, all pointing to your WAN IPv4, not `LAN_IP`. If `FLUXER_ENABLED=yes`, also add `chat`; if `QBITTORRENT_ENABLED=yes`, add `downloads`. Do not add AAAA records: DEN's published listeners and VPN are IPv4-only. Keep the apex name public; WireGuard uses it as its endpoint. DEN does not require a deSEC API token for certificate issuance.
3. Forward **TCP 80**, **TCP 443**, and **UDP 51820** to the server. Port 80 is required for Let's Encrypt HTTP-01 issuance and renewal; do not close it after installation. Do not forward Fluxer's TCP 7881 or UDP 7882: voice is for LAN/VPN clients only. Do not forward SSH, database ports, Jellyfin 8096, Immich 2283, Forgejo 3000/22, DNS 53, or Traefik 8080.
4. Add LAN DNS overrides for the four core application names, `chat` when Fluxer is enabled, and `downloads` when qBittorrent is enabled, resolving them to the server's LAN IPv4. Set clients to use that router/local DNS. Routers with NAT loopback can sometimes work without overrides, but explicit local resolution is the recommended setup. DNS overrides are router-specific; DEN does not reconfigure your router.
5. Verify your WAN address is reachable. CGNAT commonly uses `100.64.0.0/10`, or the router may have another private WAN address. Ask the ISP for public IPv4 if needed. Double NAT requires forwarding at both routers. If you have a changing WAN address, configure a deSEC-compatible DDNS updater on your router or another device for these records; DEN does not install a separate DDNS updater.

If your router cannot supply local DNS overrides and has no usable NAT loopback, do not proceed until local name resolution is solved. Having no manual *reverse proxy* setup does not remove the need for DNS and router preparation.

## deSEC Setup

Do this in a browser on your own computer, before running the DEN installer.
You need access to your domain registrar and router as well as deSEC.

1. Create an account at [deSEC](https://desec.io) and confirm the email it sends.
2. Add the domain you own, for example `example.net`. Creating a DNS zone at
   deSEC does **not** buy or register a domain. If the domain already hosts
   other services, copy its existing DNS records into deSEC before switching
   nameservers so those services keep working.
3. At the registrar where you registered the domain, change its authoritative
   nameservers to the ones supplied by deSEC. If DNSSEC is already enabled,
   coordinate the registrar's DS records with deSEC's DNSSEC instructions;
   stale DS records can make the entire domain fail to resolve.
4. Find your router's **public WAN IPv4** on its Internet/status page. This is
   different from Fedora's reserved LAN address. Create these records in
   deSEC's record editor, using type **A** and that WAN IPv4 as the value:

   | Subname in deSEC | Full DNS name | Value |
   | --- | --- | --- |
   | Empty (zone root) | `example.net` | Your public WAN IPv4 |
   | `media` | `media.example.net` | Your public WAN IPv4 |
   | `photos` | `photos.example.net` | Your public WAN IPv4 |
   | `files` | `files.example.net` | Your public WAN IPv4 |
   | `git` | `git.example.net` | Your public WAN IPv4 |
   | `chat` (optional Fluxer) | `chat.example.net` | Your public WAN IPv4 |
   | `downloads` (optional qBittorrent) | `downloads.example.net` | Your public WAN IPv4 |

   Enter only the subname in the subname field, not the full DNS name. Use the
   editor's default TTL. Do not create AAAA records for DEN names or put them
   behind a CDN/proxy. No mail records are needed for DEN.
5. Set `DOMAIN=example.net` in DEN's install config, without `https://` or a
   service prefix. `EMAIL` is your existing email address for certificate
   notices; DEN does not create a mailbox. No deSEC API token is needed by DEN:
   certificates use HTTP-01 through forwarded TCP 80, not the DNS API.
6. Allow DNS delegation and records to propagate. If `nslookup` is available,
   check `nslookup example.net 1.1.1.1` and
   `nslookup files.example.net 1.1.1.1`: both must return your public WAN IPv4.
   Separately, querying `files.example.net` using your home DNS must return
   Fedora's reserved LAN IPv4 after you set the router's local override.

A changing WAN IPv4 needs a deSEC-compatible DDNS updater that keeps **all**
these public A records current, including the root used by WireGuard. DEN
does not provide that updater; arrange it before relying on unattended access.
Keep any updater token private and separate from the non-secret handover guide.

## Away From Home

Install the WireGuard app and import `/opt/den/private/home.conf` securely onto one device. For another device:

```bash
sudo den vpn-add phone
```

Import `/opt/den/private/phone.conf` privately. Never reuse a profile across devices, publish it, or send it to a support forum. `sudo den vpn-remove phone` revokes a lost device. Take a fresh backup and refresh your external recovery kit after device changes.

The VPN is split-tunnel: only the DEN VPN subnet and your home subnet are routed home. It is not an anonymous internet VPN. VPN DNS resolves the application names to `LAN_IP` and forwards other DNS queries to Cloudflare. DNS forwarding is not encrypted DNS. On Linux clients, `DNS=` in a wg-quick profile may require the distribution's `resolvconf` integration; the official mobile apps handle it themselves.

Test from mobile data or a different network, not your own Wi-Fi. A remote network using the same subnet as your home can cause routing conflicts. Client-side encrypted/private DNS may bypass the VPN's DNS; use the WireGuard profile's resolver for DEN names.

qBittorrent uses the server's normal outbound connection, not an anonymizing
VPN. Do not forward its TCP/UDP 6881 or direct Web UI 8081 ports. Keep automatic
UPnP/NAT-PMP port mapping disabled.

## Verify the Privacy Boundary

On mobile data with VPN **off**, open each HTTPS application URL, including `chat` and `downloads` when enabled. Expect **403 Forbidden**. With VPN on, expect the app or login screen with a valid certificate. Fluxer voice ports must not be reachable from mobile data without VPN.

The access rule uses the actual connecting IPv4, not client-supplied forwarded headers. **Do not place a CDN or another reverse proxy in front of DEN. Do not use a router that source-NATs all inbound WAN traffic to its own LAN address.** That would make internet users look like trusted LAN clients. The external 403 test is a required installation gate, not an optional precaution.

App share links are private too. A friend needs their own VPN profile to use them; DEN intentionally does not create public exceptions.