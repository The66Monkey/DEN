# Router and DNS

DEN chooses a single model: publicly valid HTTPS names, with application access restricted to your LAN and WireGuard. It does not offer alternative TLS providers, tunnels, or certificate modes.

## One-Time Preparation

1. Reserve the server's LAN IPv4 in your router, for example `192.168.1.10`. This becomes `LAN_IP`; put the home subnet, for example `192.168.1.0/24`, in `LAN_CIDR`.
2. Create public DNS **A** records for your domain and `media`, `photos`, `files`, and `git` beneath it, all pointing to your WAN IPv4. If `FLUXER_ENABLED=yes`, also add `chat`. Do not add AAAA records: DEN's published listeners and VPN are IPv4-only. Keep the apex name public; WireGuard uses it as its endpoint.
3. Forward **TCP 80**, **TCP 443**, and **UDP 51820** to the server. Port 80 is required for Let's Encrypt HTTP-01 issuance and renewal; do not close it after installation. Do not forward Fluxer's TCP 7881 or UDP 7882: voice is for LAN/VPN clients only. Do not forward SSH, database ports, Jellyfin 8096, Immich 2283, Forgejo 3000/22, DNS 53, or Traefik 8080.
4. Add LAN DNS overrides for the four core application names, and `chat` when Fluxer is enabled, resolving them to the server's LAN IPv4. Set clients to use that router/local DNS. Routers with NAT loopback can sometimes work without overrides, but explicit local resolution is the recommended setup. DNS overrides are router-specific; DEN does not reconfigure your router.
5. Verify your WAN address is reachable. CGNAT commonly uses `100.64.0.0/10`, or the router may have another private WAN address. Ask the ISP for public IPv4 if needed. Double NAT requires forwarding at both routers. If you have a changing WAN address, configure your router's existing DDNS feature for these records; DEN does not install a separate DDNS updater.

If your router cannot supply local DNS overrides and has no usable NAT loopback, do not proceed until local name resolution is solved. Having no manual *reverse proxy* setup does not remove the need for DNS and router preparation.

## Away From Home

Install the WireGuard app and import `/opt/den/private/home.conf` securely onto one device. For another device:

```bash
sudo den vpn-add phone
```

Import `/opt/den/private/phone.conf` privately. Never reuse a profile across devices, publish it, or send it to a support forum. `sudo den vpn-remove phone` revokes a lost device. Take a fresh backup and refresh your external recovery kit after device changes.

The VPN is split-tunnel: only the DEN VPN subnet and your home subnet are routed home. It is not an anonymous internet VPN. VPN DNS resolves the application names to `LAN_IP` and forwards other DNS queries to Cloudflare. DNS forwarding is not encrypted DNS. On Linux clients, `DNS=` in a wg-quick profile may require the distribution's `resolvconf` integration; the official mobile apps handle it themselves.

Test from mobile data or a different network, not your own Wi-Fi. A remote network using the same subnet as your home can cause routing conflicts. Client-side encrypted/private DNS may bypass the VPN's DNS; use the WireGuard profile's resolver for DEN names.

## Verify the Privacy Boundary

On mobile data with VPN **off**, open each HTTPS application URL, including `chat` when enabled. Expect **403 Forbidden**. With VPN on, expect the app or login screen with a valid certificate. Fluxer voice ports must not be reachable from mobile data without VPN.

The access rule uses the actual connecting IPv4, not client-supplied forwarded headers. **Do not place a CDN or another reverse proxy in front of DEN. Do not use a router that source-NATs all inbound WAN traffic to its own LAN address.** That would make internet users look like trusted LAN clients. The external 403 test is a required installation gate, not an optional precaution.

App share links are private too. A friend needs their own VPN profile to use them; DEN intentionally does not create public exceptions.