# Something Not Working?

Connect over SSH and start here:

```bash
sudo den status
sudo den check
systemctl --failed
```

| Problem | Try |
| --- | --- |
| App URL fails on LAN or shows a TLS error | Enable WireGuard, or point the app's local DNS name to DEN's LAN IP. Use the hostname, not the bare IP. |
| Certificate is not ready | Wait a few minutes, then run `sudo den logs traefik`. Check [DNS and certificate setup](networking.md). |
| WireGuard will not connect | Forward **UDP**, not TCP, port 41873. Test on mobile data. Check the `vpn` DNS record (or the endpoint in a legacy profile) and `sudo wg show`. |
| VPN connects but names fail | Disable browser/device Secure DNS that bypasses VPN DNS. Check `systemctl status den-dns`. |
| Profile was not created | Use a lowercase device name and the same name in every command. See [profile download](installation.md#import-wireguard-on-another-computer). |
| Outside access fails without VPN | Expected for private apps. Enabled Fluxer needs public TCP 443 routed to DEN; if BASM owns that forward, plan the cutover first. |
| Completed movies are missing | Add `/downloads/complete` as a Jellyfin library, then scan. Other media uses `/media/movies`, `/media/tv` or `/media/music`. |
| qBittorrent password stopped working | Set a permanent password; the initial temporary one changes after restart. Find it with `sudo den logs qbittorrent`. |
| Nextcloud is still starting | Allow several minutes, check free space, then `sudo den logs nextcloud`. |
| Fluxer is unavailable | Run `sudo den fluxer-status` and `sudo rexctl --dir /opt/den/fluxer doctor`. Check the `chat` DNS name. |
| Calls fail | Forward TCP 7881 and UDP 7882 to DEN; run `sudo rexctl --dir /opt/den/fluxer voice test`. Public voice IP discovery and router hairpin support matter; see [public calls](networking.md#public-chat-and-calls). |
| Another operation is running | Wait for the backup or update to finish. |
| Backup fails or disk is full | Check `df -h` and `journalctl -u den-backup.service -n 50`. See [backups](backup.md). |
| HDD missing / Docker will not start | Reconnect the configured HDD. Check `findmnt /srv/den/media` and `findmnt /srv/den/downloads`, then `systemctl status srv-den-media.mount srv-den-downloads.mount docker`. |
| Update failed | Read `journalctl -u den-update.service -n 50`. Do not remove its marker or downgrade database images; see [recovery](backup.md#recover-after-a-bad-update). |

Do not delete `/opt/den/.env`, data folders or backups to retry setup.
Do not disable SELinux or the firewall. Failed installation does not yet support
automatic resume: `sudo den start` starts prepared apps but cannot complete
missing host configuration. Save the error and ask for help.

## Browser still says "Not secure"

First verify the full `https://` hostname, the certificate's hostname, issuer and
expiry, and that DNS reaches the intended server. A private window that reports
a secure connection while an old normal tab does not suggests browser-local
state, such as a prior certificate exception. Close old tabs and restart the
browser; if necessary, reset that site's permissions/data (this may sign you out).
If a fresh window also reports a problem, inspect its security explanation for
certificate errors or mixed content instead of assuming a cache issue.
Do not disable certificate validation, trust a proxy's default self-signed
certificate or repeatedly request new ACME certificates to fix browser state.

For deeper diagnosis, [architecture](architecture.md) lists paths and firewall
commands. Redact passwords, tokens and VPN keys before sharing logs.
