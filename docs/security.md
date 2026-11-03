# Access and Privacy

- Photos, files, media, Git and downloads work only on LAN/VPN. Enabled Fluxer
  chat and calls are public, with invite-only registration and app logins.
- Use a separate lowercase WireGuard profile for each device. Revoke a lost
  device with `sudo den vpn-remove DEVICE-NAME`.
- Keep passwords, VPN QR codes, profiles and recovery kits private.
  Logs can contain passwords; redact them before sharing.
- Finish initial admin setup before sharing access. Use personal accounts daily.
  Email password resets are not configured.
- Keep firewalld and SELinux enabled. Forward only the [documented ports](networking.md#port-forwarding).
- qBittorrent defaults to your normal public IP; home-access WireGuard does not
  hide it. The optional [torrent-only provider VPN](qbittorrent.md#optional-torrent-vpn)
  has a kill switch and no automatic direct fallback. Keep its private profile
  out of Git; a VPN is not anonymity.
- Backups are encrypted; DEN does not encrypt live files. Sharing a media and
  backup HDD means its failure loses both.
- Keep a KeePass vault's master password separate from its exported file.
  App passwords changed outside DEN must be updated in the vault manually.
- Keep owner/admin, family-shared and personal vaults separate. Never share the
  owner vault to distribute ordinary family credentials. See
  [password-vault access](keepass-sharing.md) for private shared-file access,
  permissions, synchronization and recovery limitations.

For administrators: Docker/root access controls the entire server. Containers
share a network, not strong isolation. Only use a trusted update repository;
its code runs as root. Source-hiding proxies or router source NAT can undermine
LAN restrictions. See [architecture](architecture.md) for implementation details.
