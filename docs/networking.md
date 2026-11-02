# Router and DNS Setup

Use WireGuard for private apps away from home. Enabled Fluxer chat/calls are public.
WireGuard also supplies the correct DNS.
For LAN devices without VPN, set local DNS as described below.

## deSEC Setup

1. Add your domain at [deSEC](https://desec.io). If registered elsewhere,
   follow deSEC's nameserver instructions; keep existing records you still need.
2. Create these **A records**, all pointing to your router's **public IPv4**:

   | Name | Service |
   | --- | --- |
   | `home` | WireGuard and LAN/VPN-only DEN home page |
   | `media` | Jellyfin |
   | `photos` | Immich |
   | `files` | Nextcloud |
   | `git` | Forgejo |
   | `chat` | Optional Fluxer |
   | `downloads` | Optional qBittorrent |

3. Create an API token for DNS updates. DEN asks for it during installation.
   With `ACME_CHALLENGE=dns-desec`, allow certificate challenge TXT changes too.

Set `DOMAIN` to the domain alone, without a service prefix or `https://`.
Do not add AAAA records for DEN names. DEN updates public IPv4 records
automatically; the domain's root record is left unchanged.

## Port Forwarding

Reserve the server's LAN IP in your router, then forward:

| Install setting | Ports forwarded to DEN |
| --- | --- |
| `ACME_CHALLENGE=dns-desec`, Fluxer off | **UDP 41873** only |
| `ACME_CHALLENGE=http` | TCP 80, TCP 443 and **UDP 41873** |
| Fluxer enabled (either certificate mode) | Also **TCP 443, TCP 7881, UDP 7882** |

UDP matters: a TCP rule for 41873 will not work.
Use the same external/internal port numbers. Do not forward SSH, Cockpit,
Fluxer's HTTP backend (29461), or database ports.
Your ISP must provide a reachable public IPv4; ask them if you are behind CGNAT.

### Coexisting with Another Web Server

Use `ACME_CHALLENGE=dns-desec`. Leave the other server's TCP 80/443 forwards
unchanged and forward only UDP 41873 to DEN **when Fluxer is disabled**.
Public Fluxer needs TCP 443 routed directly to DEN; DNS certificates alone do
not route browser traffic. With one public IP, both servers cannot own that
forward. Plan a cutover before enabling public chat; shared external-proxy
routing is not configured by DEN. Certificates can take several minutes.

### Public Chat and Calls

Enabling `FLUXER_ENABLED=yes` makes only the `chat` HTTPS route public.
Registration stays invite-only; app authentication remains required.
Other HTTPS apps retain their LAN/VPN allowlist even though TCP 443 is reachable.
Traefik handles chat/API WebSockets as well as HTTPS.

Calls use TCP 7881 and UDP 7882 directly, not the web proxy. Rexctl/LiveKit
automatically discovers the public voice IP. Installation no longer forces a
LAN address; updates and recovery remove the previous `voice.public_ip` override.
If the WAN IP changes, DNS refreshes automatically; if calls advertise a stale
address, restart Fluxer and test again:

```bash
sudo rexctl --dir /opt/den/fluxer restart
sudo rexctl --dir /opt/den/fluxer voice test
```

Test a call between devices on different external networks, with VPN off.
For home clients, the router needs NAT loopback/hairpin support for the public
voice address. A VPN alone does not guarantee this; verify home-to-outside calls
as well as calls between external networks.
STUN discovery is not a relay: restrictive client networks may need an upstream
TURN setup, which DEN does not provision.

**Existing installs:** applying this release with Fluxer enabled changes chat
from private to public and may restart Fluxer while resetting voice discovery.
Review router forwarding before updating. This does not migrate a BASM Fluxer
instance or change its domain; retain your current instance until a separate,
backup-based migration and cutover are ready.

## Router and Local DNS

In the router's local DNS settings, point each enabled app name to DEN's
**LAN IP**, for example:

```text
192.168.1.10 media.example.net photos.example.net files.example.net git.example.net
192.168.1.10 chat.example.net downloads.example.net
```

Keep `home.example.net` pointing to the **public IP** for WireGuard.
To open `https://home.example.net` on the LAN without changing that VPN endpoint,
use router NAT loopback/hairpin support, or connect through WireGuard (whose DNS
resolves it to the LAN IP). Do not override `home` to the LAN IP in router DNS:
VPN clients still need its public address to establish the tunnel.
The home page includes service links, LAN SSH instructions and the installed README.
It retains the LAN/VPN allowlist even when chat is public.
Devices must use the router's DNS; browser Secure DNS can bypass it.
If the router has no local DNS overrides, use WireGuard or add these entries
to each computer's hosts file.

Open apps by hostname, not IP. A bare IP gives a 404 or certificate error.
Public DNS may send you to another server, even from home.

## Verify Access

- LAN with local DNS, or VPN on: app URLs open with valid HTTPS.
- Mobile data with VPN off: enabled chat loads with valid HTTPS and calls work;
  photos/files/media/Git/downloads are denied (normally HTTP 403 with public chat).
- Mobile data with VPN on: apps work.

If another server handles public HTTPS, its response with VPN off is unrelated
to DEN. Do not change its forwards to fix DEN's local DNS.

## LAN/VPN Network Guard

DEN's firewall keeps private apps and administration on LAN/VPN; enabled Fluxer
admits public HTTPS and voice. Leave firewalld and
SELinux enabled. Avoid source-hiding proxies/CDNs or router rules that make
outside traffic appear to come from a LAN device.

Existing Cockpit is available at `https://SERVER-LAN-IP:9090` with your Fedora
login. It uses its own certificate, not the app certificates.
For firewall internals, see [architecture](architecture.md).

## WireGuard Away from Home

Use a unique lowercase profile name per device.
See [phone QR setup](installation.md#connect-your-phone-with-wireguard) or
[computer profile download](installation.md#import-wireguard-on-another-computer).
Revoke a lost device with `sudo den vpn-remove DEVICE-NAME`.

Only home-network traffic uses the tunnel, not ordinary internet browsing.
If the remote Wi-Fi uses the same subnet as home, try mobile data.
