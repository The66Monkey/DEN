# Access and Privacy

- Apps work only on LAN/VPN and still require their own logins.
- Use a separate lowercase WireGuard profile for each device. Revoke a lost
  device with `sudo den vpn-remove DEVICE-NAME`.
- Keep passwords, VPN QR codes, profiles and recovery kits private.
  Logs can contain passwords; redact them before sharing.
- Finish initial admin setup before sharing access. Use personal accounts daily.
  Email password resets are not configured.
- Keep firewalld and SELinux enabled. Forward only the [documented ports](networking.md#port-forwarding).
- qBittorrent uses your normal internet connection. WireGuard does not hide
  downloads from trackers or peers.
- Backups are encrypted; DEN does not encrypt live files. Sharing a media and
  backup HDD means its failure loses both.
- Keep a KeePass vault's master password separate from its exported file.
  App passwords changed outside DEN must be updated in the vault manually.

For administrators: Docker/root access controls the entire server. Containers
share a network, not strong isolation. Only use a trusted update repository;
its code runs as root. Source-hiding proxies or router source NAT can undermine
LAN restrictions. See [architecture](architecture.md) for implementation details.
