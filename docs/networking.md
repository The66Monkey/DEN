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
   | `vpn` | Public WireGuard endpoint (never a private DNS rewrite) |
   | `home` | LAN/VPN-only DEN home page |
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

### deSEC Form Fields and Existing Records

Choose **A** under **Record set type**, enter the service prefix (for example
`media`) under **Subname**, and enter your router's public IPv4 under
**IPv4 address**. TTL `3600` is suitable for initial setup. Subname is relative
to your domain: do not enter the full hostname. For a root-domain record,
deSEC uses a **blank Subname**, not `@`; DEN does not manage that root record.

deSEC requires surrounding double quotation marks for **TXT** content, such
as `"example text"`. Certificate TXT records under `_acme-challenge` are managed
by the ACME client in `dns-desec` mode; do not edit or remove them during issuance
or renewal. A certificate challenge record is not an app's A record.

Do not wipe an existing DNS zone. Keep its NS records and records needed by
other services, and export the records before migration changes.

DEN and BASM can share a zone with separate API tokens and non-overlapping
record permissions: DEN owns the names listed above, while BASM normally owns
the root, `erp`, `mail`, `cloud` and `mx`. If DEN owns `chat`, leave BASM Fluxer
unselected or choose a distinct BASM hostname. DDNS only updates addresses;
Postal's MX, SPF, DKIM and DMARC setup belongs to BASM. DNS records alone do not
solve the shared public HTTPS forwarding limitation described below.

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
Public Fluxer needs TCP 443 routed to DEN's edge; DNS certificates alone do
not route browser traffic. With one public IP, both servers cannot own that
forward. Plan a cutover before enabling public chat; shared external-proxy
routing is not configured by DEN. Certificates can take several minutes.

For an explicitly managed shared front door instead of separate forwards, see
[independent DNS and shared HTTPS edge](infrastructure.md). This optional
topology moves ingress and LAN DNS outside the business VM without making
private DEN apps public.

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

Keep `vpn.example.net` pointing to the **public IP** in every resolver.
Separately installed applications manage their own exact LAN DNS rewrites,
private routes and certificate prerequisites. Core DDNS only manages core app
names. See [add-on integration](addons.md); never make an extra application
public by broadening the core LAN/VPN allowlist.
The installer and `vpn-add` now generate `vpn.DOMAIN` endpoints. Existing device
profiles using `home.DOMAIN` must be edited before adding a private `home` rewrite:
replace only the endpoint hostname, preserving the port, keys and AllowedIPs.
Test a disconnect/reconnect on mobile data. Saved server profiles do not update
already-imported device profiles; older KeePass attachments may also retain
the old endpoint. No key rotation or new peer is needed for a hostname edit.

Add `home.example.net` to the private DEN app records after that transition.
The home page includes service links, LAN SSH instructions, the mascot and a
GitHub link.
It retains the LAN/VPN allowlist even when chat is public.
Devices must use the private resolver; browser Secure DNS can bypass it.
If the router has no local DNS overrides, use WireGuard or add these entries
to each computer's hosts file.

DEN's VPN DNS now overrides only enabled DEN service names, not the entire
domain. Other names, including `vpn` and BASM services, resolve upstream unless
an administrator supplies explicit coexistence records. Existing deployments
need a reviewed DNS configuration update; do not rerun `write_vpn` or the
installer to change DNS, since initial VPN setup generates new keys.

### LAN DNS with BASM and a private resolver

When using AdGuard or another private resolver, configure exact rewrites:
DEN's enabled web names to DEN's LAN address, BASM's `erp`, `mail`, `cloud` to
BASM's LAN address. Keep the same service separation in VPN DNS.
`vpn.example.net` must stay public. Preserve public service records.
If using a filtering provider, configure it as the private resolver's upstream,
not a secondary resolver advertised directly to LAN clients.

When DEN runs independent AdGuard infrastructure, add
`dns.example.com -> DEN-LAN-IP` to the private resolver and open
`https://dns.example.com` to administer it (replace the domain).
See [AdGuard administration and device filtering](infrastructure.md#adguard-administration-dnsexamplecom).
This name stays out of public DDNS; it points to the shared edge, not the BASM VM.

On the ASUS RT-AX58U, configure **LAN > DHCP Server > DNS and WINS Server
Setting > DNS Server** to the private resolver's LAN address. Leave a second public DNS blank.
If shown, disable **Advertise router's IP in addition to user-specified DNS**.
DNS Director/Filter rules forcing CleanBrowsing directly must not bypass AdGuard;
disable that redirect or set an appropriate custom resolver after reviewing
device exceptions. WAN DNS can remain separate. Renew DHCP/reconnect Wi-Fi and
clear resolver/browser caches. Test with VPN off: `nslookup home.DOMAIN` must
return DEN's LAN address, while `nslookup vpn.DOMAIN` must return the public IP.
IPv6-advertised DNS and browser Secure DNS can also bypass private rewrites.
Do not publicly expose AdGuard's DNS/admin ports.

Open apps by hostname, not IP. `https://SERVER-LAN-IP/` serves only the DEN
home page, still restricted to LAN/VPN. The IP route does not request an ACME
certificate, so browsers normally show a certificate warning there. For trusted
HTTPS use `https://home.DOMAIN/` with the local/VPN DNS arrangement above.
Public DNS may send you to another server, even from home.

If `home.DOMAIN` shows `TRAEFIK DEFAULT CERT` but direct LAN access with that
hostname serves a trusted certificate, the browser is reaching the wrong
reverse proxy, not a broken DEN certificate. Use DEN's VPN DNS or a per-device
hosts entry for the home page (`SERVER-LAN-IP home.DOMAIN`). First migrate legacy
`home.DOMAIN` VPN endpoints to `vpn.DOMAIN` as described above.
Do not change the public endpoint record to a private IP.
Do not install a default self-signed proxy certificate as trusted or use browser
exceptions as the normal access procedure.

## Optional balanced IoT protection

DEN supports a separate TV Wi-Fi network with DNS and Jellyfin access through
`TV_CIDR`. The setting is empty by default: existing installations keep their
current access policy. Enabling it creates a restricted firewall zone and a
Jellyfin-only HTTPS exception. AdGuard administration and other private apps
remain on the trusted LAN/VPN. The router supplies Wi-Fi isolation and internet.

### 1. Set up filtering before changing DHCP DNS

Follow [independent AdGuard setup](infrastructure.md), then open
`https://dns.example.com` from the trusted LAN (use your domain).

Use these settings for a new AdGuard installation:

| AdGuard setting | Balanced value |
| --- | --- |
| Protection / DNS filtering | Enabled |
| DNS blocklists | AdGuard DNS filter enabled; retain its automatic refresh |
| Upstream DNS | `https://dns.quad9.net/dns-query` |
| Bootstrap DNS | `9.9.9.9`, `149.112.112.112` |
| Query log | Enabled for diagnosing blocked or unfiltered requests |
| Broad vendor/app lists | No additional lists in the baseline |

For an existing resolver, retain its working upstream, filters, administrator
account and client exceptions. Export the router's current blocked-domain list
before moving clients. Transfer rules you still require under **Filters > Custom
filtering rules**, scoped to the device's reserved IP where appropriate.
Verify a previously blocked hostname in **Query Log** before making AdGuard the
DHCP resolver. This avoids losing existing protection during migration.

### 2. Configure TV Wi-Fi on the router

Example addresses below assume DEN is `192.168.1.10`, the trusted LAN is
`192.168.1.0/24`, and the new TV network is `192.168.60.0/24`. Replace these with
your own non-overlapping subnets.

1. Create a separate TV SSID/subnet and enable Wi-Fi client isolation.
2. Set DHCP DNS to DEN's address only and reserve the TV's IP
   (for example `192.168.60.201`).
3. Apply the following rules in order, retaining established return traffic:

   | Source | Destination | Traffic | Action |
   | --- | --- | --- | --- |
   | TV network | DEN `192.168.1.10` | TCP/UDP 53, TCP 443 | Allow |
   | TV network | Other private networks and router administration | New connections | Deny |
   | TV network | Other DNS destinations | TCP/UDP 53 and 853 | Deny |
   | TV network | Internet | Other outbound traffic | Allow |

4. Use IPv4-only on this SSID for this profile. Enable IPv6 later only with
   matching isolation and DNS rules.
5. Route TV traffic to DEN with the TV's original source address, without
   source NAT between these subnets.

The router must support a separate subnet and these narrow LAN exceptions.
On ASUS firmware with only an **Access Intranet** on/off guest option, leave
intranet access disabled: that mode supplies internet-only guest Wi-Fi, not
this Jellyfin profile. Use a VLAN/SSID-capable gateway for the full profile;
enabling general intranet access would undo the separation.

### 3. Enable DNS and Jellyfin in DEN

On an existing DEN, update to a release containing `tv-setup`, save a copy of
`/opt/den/.env`, and add or edit this single setting:

```text
TV_CIDR=192.168.60.0/24
```

Leave `LAN_CIDR` as the trusted LAN. Then run:

```bash
sudo den tv-setup
```

The command applies DEN's pre-DNAT network guard, the `den-tv` firewall zone,
and the Jellyfin route. It preserves other custom routes and does not recreate
VPN keys, application containers or DNS filters. Updates and recovery use the
saved setting. Overlapping, public or non-canonical TV subnets are rejected.
Independent AdGuard infrastructure is required.

In AdGuard **Settings > DNS settings > Access settings > Allowed clients**, add
`192.168.60.0/24` alongside the existing trusted LAN/VPN and DNS-container
entries. Under **Filters > DNS rewrites**, add:

```text
media.example.com -> 192.168.1.10
```

Enter `https://media.example.com` in the TV's Jellyfin app and use its normal
Jellyfin account. The profile permits that HTTPS route only; it does not add
cross-network casting/discovery.

### 4. Check and undo

From a device on TV Wi-Fi, verify:

- `nslookup media.example.com 192.168.1.10` returns DEN's address.
- Jellyfin login, playback and seeking work.
- `https://dns.example.com`, `https://files.example.com` and DEN's IP home page
  return HTTP 403; SSH/Cockpit and trusted computers are inaccessible.
- AdGuard shows the TV's own source IP and expected blocked requests.
- SVT Play, Netflix and the TV account/update check still work.
- A second client on that SSID is isolated; repeat after router/DEN reboot.

If an app breaks, inspect its requests in AdGuard and create a per-TV exception
for the specific required hostname. Keep the two subnet rules intact.

To remove DEN's TV exception, set `TV_CIDR=` and run `sudo den tv-setup` again.
Remove the TV subnet from AdGuard's allowed clients and remove the router's
DEN-access exception. Use the trusted LAN to administer DEN throughout setup.

### Stronger filtering, separately

The baseline isolates LAN scanning and uses DNS filtering while retaining
streaming compatibility. It does not block every direct-IP telemetry connection
or DNS-over-HTTPS on TCP 443. For additional blocking, put reviewed per-device
destination-IP rules on the gateway; streaming providers share and change IPs,
so test playback after each addition. Keep such rules outside DEN's defaults.
The optional [per-TV AdGuard examples](infrastructure.md#device-specific-filtering)
are likewise separate from the standard filter.

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

With `COCKPIT_ENABLED=yes` (default), open `https://server.YOUR-DOMAIN/`
from the trusted LAN or VPN and log in with your Fedora account.
Add the exact LAN DNS rewrite `server.YOUR-DOMAIN → SERVER-LAN-IP`;
DEN manages the matching VPN record and public A record for certificate issuance.
The TV subnet is excluded. Cockpit listens on DEN's Docker gateway, accessible
only to its HTTPS proxy; the backend certificate is verified.
Opt-out and existing-install activation: [Cockpit administration](operations.md#cockpit-administration).
For firewall internals, see [architecture](architecture.md).

## WireGuard Away from Home

Use a unique lowercase profile name per device.
See [phone QR setup](installation.md#connect-your-phone-with-wireguard) or
[computer profile download](installation.md#import-wireguard-on-another-computer).
Revoke a lost device with `sudo den vpn-remove DEVICE-NAME`.

Only home-network traffic uses the tunnel, not ordinary internet browsing.
If the remote Wi-Fi uses the same subnet as home, try mobile data.
