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

## LAN/VPN network guard

DEN installs `den-firewall.service` and `/etc/den/network.nft`. This separate
nftables table filters ingress **before Docker destination NAT**, so
Docker-published ports cannot bypass the LAN/VPN restriction.

- Devices in `LAN_CIDR` can use the server without a VPN; application logins
  still apply. Local DNS overrides are needed for the HTTPS names.
- Outside that subnet, UDP 41873 is the remote entry point. Authenticated
  WireGuard devices can use the web apps, SSH, Cockpit on TCP 9090, VPN DNS
  and enabled Fluxer voice ports, and reach the configured LAN.
- DNS-01 permits no unsolicited public web/admin/voice access. HTTP-01 keeps
  only public TCP 80 as an additional exception for certificate challenges.
- Return traffic for outbound connections, DHCP and necessary IPv6 network
  control messages remain allowed. IPv6 does not provide an alternative path
  into application or administration listeners.
- Docker's internal bridges remain trusted for application communication.
  This is an edge-access policy, not isolation between containers.

The guard is enabled at boot and required before Docker starts. Firewalld
stays enabled and uses a dedicated `den-vpn` zone instead of putting `wg0`
in the general `trusted` zone; the guard bounds that zone's accepted traffic.
Cockpit's socket is not enabled automatically, but an existing Cockpit
installation remains usable from LAN/VPN.
Open `https://SERVER-LAN-IP:9090` and sign in with your Fedora account.
Cockpit uses its own certificate, not Traefik's application certificates;
verify its identity before trusting a self-signed certificate.

`sudo den check` verifies that the guard service and table are present.
Inspect with `sudo nft list table inet den_guard`; validate and reload with
`sudo nft --check --file /etc/den/network.nft` and
`sudo systemctl reload den-firewall`. Reloads replace only DEN's table,
not Docker or firewalld rules. Stopping the service does not erase its rules.
Installation, recovery and release updates regenerate the policy from the
saved environment.

Do not source-NAT forwarded internet traffic to a LAN address: the server
cannot distinguish it from a genuine LAN device. Keep only the documented
router forwards, disable automatic router port mapping, and do not expose
DEN through a proxy that hides source addresses.

## Verify access

Test from mobile data or another external network, not your home Wi-Fi:

- With VPN **off**, outside traffic must not reach DEN applications or administration. The network guard normally drops it (connection timeout); Traefik also returns **403 Forbidden** to untrusted sources that reach its allowlist. In DNS-01 coexistence mode, public traffic can reach your other server instead.
- With VPN **on**, each URL must show the application or login page with a valid certificate.
- Fluxer voice ports must not be reachable from mobile data without VPN.

Do not put a CDN or another reverse proxy in front of DEN, or use a router that source-NATs inbound traffic to its LAN address. Either can hide the connecting address and make external users appear to be on the trusted LAN.

## WireGuard away from home

Import `/opt/den/private/home.conf` securely onto one device. For each additional device, create a separate profile:

```bash
sudo den vpn-add phone
```

To import without copying the profile by hand, SSH into the server from a
computer on your home network:

```bash
ssh YOUR-FEDORA-USER@SERVER-LAN-IP
sudo sh -c 'qrencode -t ansiutf8 < /opt/den/private/phone.conf'
```

`qrencode` is installed as standard. In the phone's WireGuard app, add a
tunnel by scanning the QR code in your computer's terminal. If you have not
created `phone` yet, run `sudo den vpn-add phone` first; do not recreate an
existing profile. The initial `home.conf` can also be scanned, but must be
used on only one device.

The QR code contains a private key: never share it or post screenshots.
Alternatively, import the configuration file through a private transfer.
Never reuse or publish profiles. Revoke a lost device with
`sudo den vpn-remove phone`. Disable phone Wi-Fi and test the tunnel on mobile
data, with UDP 41873 forwarded to the server.

The VPN is split-tunnel: only the DEN VPN subnet and your home subnet route through the server. Client encrypted/private DNS can bypass VPN DNS; use the profile's resolver for DEN names. A remote network using the same subnet as home can cause routing conflicts.
