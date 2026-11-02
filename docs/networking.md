# Router and DNS Setup

Use WireGuard for access away from home. It also supplies the correct DNS.
For LAN devices without VPN, set local DNS as described below.

## deSEC Setup

1. Add your domain at [deSEC](https://desec.io). If registered elsewhere,
   follow deSEC's nameserver instructions; keep existing records you still need.
2. Create these **A records**, all pointing to your router's **public IPv4**:

   | Name | Service |
   | --- | --- |
   | `home` | WireGuard |
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
| `ACME_CHALLENGE=dns-desec` | **UDP 41873** only |
| `ACME_CHALLENGE=http` | TCP 80, TCP 443 and **UDP 41873** |

UDP matters: a TCP rule for 41873 will not work.
Do not forward SSH, Cockpit, voice or database ports.
Your ISP must provide a reachable public IPv4; ask them if you are behind CGNAT.

### Coexisting with Another Web Server

Use `ACME_CHALLENGE=dns-desec`. Leave the other server's TCP 80/443 forwards
unchanged and forward only UDP 41873 to DEN. Certificates use DNS validation,
which can take several minutes. Outside access to DEN then uses WireGuard.

## Router and Local DNS

In the router's local DNS settings, point each enabled app name to DEN's
**LAN IP**, for example:

```text
192.168.50.58 media.example.net photos.example.net files.example.net git.example.net
192.168.50.58 chat.example.net downloads.example.net
```

Keep `home.example.net` pointing to the **public IP** for WireGuard.
Devices must use the router's DNS; browser Secure DNS can bypass it.
If the router has no local DNS overrides, use WireGuard or add these entries
to each computer's hosts file.

Open apps by hostname, not IP. A bare IP gives a 404 or certificate error.
Public DNS may send you to another server, even from home.

## Verify Access

- LAN with local DNS, or VPN on: app URLs open with valid HTTPS.
- Mobile data with VPN off: DEN apps are blocked.
- Mobile data with VPN on: apps work.

If another server handles public HTTPS, its response with VPN off is unrelated
to DEN. Do not change its forwards to fix DEN's local DNS.

## LAN/VPN Network Guard

DEN's firewall keeps apps and administration on LAN/VPN. Leave firewalld and
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
