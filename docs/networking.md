# Networking and DNS

DEN requires a public domain and IPv4 connectivity. Applications use public HTTPS names, but access is restricted to your home network and WireGuard.

## DNS records

Create these **public A records** at [deSEC](https://desec.io). Replace `<DOMAIN>` with the value of `DOMAIN` (for example, `scandinavianhacking.dedyn.io`); every record must point to your current **WAN IPv4**, not the server's LAN address.

| Subname in deSEC | Full DNS name | Required? | Used for |
|---|---|---|---|
| `home` | `home.<DOMAIN>` | Required | WireGuard endpoint |
| `media` | `media.<DOMAIN>` | Required | Jellyfin |
| `photos` | `photos.<DOMAIN>` | Required | Immich |
| `files` | `files.<DOMAIN>` | Required | Nextcloud |
| `git` | `git.<DOMAIN>` | Required | Forgejo |
| `chat` | `chat.<DOMAIN>` | Optional | Fluxer; only when `FLUXER_ENABLED=yes` |
| `downloads` | `downloads.<DOMAIN>` | Optional | qBittorrent; only when `QBITTORRENT_ENABLED=yes` |

The apex (`@`, shown as `-` in deSEC) can keep pointing to another server. DEN updates only the records above, including optional records only when their applications are enabled. Do not create AAAA records for DEN names: its listeners and VPN support IPv4 only. No MX, TXT, or wildcard records are needed. Any restrictive CAA policy must allow Let's Encrypt.

## deSEC setup

1. Create a deSEC account and add your DNS zone. For a registered domain, configure the registrar's nameservers and DNSSEC as deSEC instructs; preserve any existing records before changing delegation. Creating a zone does not register a domain.
2. Add the A records above, entering only the subname in deSEC's subname field. The default TTL is fine.
3. Set `DOMAIN` to the zone name, without `https://` or a service prefix. `EMAIL` is your existing certificate contact address, not a DEN mailbox.
4. Create a deSEC API token permitted to update DEN's records. The installer prompts for it privately and stores it in root-only `/opt/den/private/ddns.env`.

DEN checks the public IPv4 at installation and every four hours, updating the records when it changes. Certificates default to HTTP-01 through TCP 80. Check updater logs with `sudo journalctl -u den-ddns`.

### Coexisting with another web server

Set `ACME_CHALLENGE=dns-desec` before installation to issue and renew
certificates through deSEC DNS-01 instead. The deSEC token must also permit
creating and deleting TXT records at `_acme-challenge` beneath each enabled
application name. Traefik receives the token through a protected file, not a
command-line argument. It waits up to ten minutes for authoritative DNS
propagation; certificate issuance is not immediate.

With DNS-01 and VPN-only remote access, forward **only UDP 41873** to DEN.
Leave existing TCP 80/443 forwards pointing to your other server. DEN still
listens on its own LAN address on standard TCP 80/443; local DNS overrides
and the WireGuard DNS server direct clients to that address. No alternate
HTTPS ports are needed. Do not expect a direct public DEN URL to reach DEN
without the VPN in this mode.

Allow DNS changes to propagate. For example, `nslookup home.<DOMAIN> 1.1.1.1` and `nslookup files.<DOMAIN> 1.1.1.1` must return your WAN IPv4. A local lookup of `files.<DOMAIN>` should return the server's LAN IPv4 after configuring local DNS.

## Router and local DNS

1. Find the server's LAN IPv4 with `hostname -I` and reserve it in your router. Set `LAN_IP` and your home subnet as `LAN_CIDR` in the install configuration.
2. Normally, forward **TCP 80**, **TCP 443**, and **UDP 41873** to the server. TCP 80 is needed for HTTP-01 certificate issuance and renewal; leave it open. For `ACME_CHALLENGE=dns-desec` with VPN-only remote access, forward only UDP 41873 as described above. DEN's WireGuard port is fixed in `lib/core.sh`.
3. Add local DNS overrides for `media`, `photos`, `files`, and `git`, plus enabled optional application names, resolving them to the server's LAN IPv4. Configure clients to use that local DNS. NAT loopback may work instead, but overrides are recommended.

Do not forward application or administration ports, including Fluxer voice (TCP 7881/UDP 7882), SSH, databases, DNS 53, or proxy-backend ports. DEN does not configure router DNS or port forwarding.

Confirm your router has a public WAN IPv4. CGNAT (`100.64.0.0/10`) or a private WAN address usually prevents inbound connections; ask your ISP for public IPv4. With double NAT, forward the ports on both routers. Solve local name resolution before installing.

## Verify access

Test from mobile data or another external network, not your home Wi-Fi:

- With VPN **off**, every enabled HTTPS application must return **403 Forbidden** if forwarding TCP 443 to DEN. In DNS-01 VPN-only mode, public traffic goes to the other server instead and must not reach DEN.
- With VPN **on**, each URL must show the application or login page with a valid certificate.
- Fluxer voice ports must not be reachable from mobile data without VPN.

Do not put a CDN or another reverse proxy in front of DEN, or use a router that source-NATs inbound traffic to its LAN address. Either can hide the connecting address and make external users appear to be on the trusted LAN.

## WireGuard away from home

Import `/opt/den/private/home.conf` securely onto one device. For each additional device, create a separate profile:

```bash
sudo den vpn-add phone
```

Import `/opt/den/private/phone.conf` privately. Never reuse or publish profiles. Revoke a lost device with `sudo den vpn-remove phone`.

The VPN is split-tunnel: only the DEN VPN subnet and your home subnet route through the server. Client encrypted/private DNS can bypass VPN DNS; use the profile's resolver for DEN names. A remote network using the same subnet as home can cause routing conflicts.
