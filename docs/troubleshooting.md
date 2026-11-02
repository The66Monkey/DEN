# Troubleshooting

Start with `sudo den status`, `sudo den check`, and `systemctl --failed`. Keep your generated `.env` and data; do not delete them to retry setup.

| Symptom | Check |
| --- | --- |
| Installer rejects OS | Fedora Server on x86_64 is the supported target. Fedora Workstation can be used for development checks. |
| Wi-Fi adapter is missing | Identify the chipset with `lsusb` or `lspci -nnk`, then inspect `journalctl -k -b` for firmware or driver errors. DEN does not build third-party modules; check whether the adapter works after a kernel update before depending on it for server access. |
| Container cannot read its data | Check `sudo ausearch -m AVC -ts recent` for SELinux denials and verify the Compose bind mount uses the shared `z` label. Do not disable SELinux as a workaround. |
| CPU rejected or ML exits | Immich 3 requires x86-64-v2. A VM may need host CPU passthrough. Do not use an unsupported old Immich release just to suppress the check. |
| TCP port conflict | Stop the old web/proxy service or use a fresh server. DEN does not choose alternative ports. |
| Wrong or unassigned address | Reserve the server's address and compare `ip -4 address` with `LAN_IP`. |
| HTTPS warning | Check public A records, remove AAAA records, forward TCP 80/443, check CAA policy permits Let's Encrypt, then inspect `sudo den logs traefik`. Never click through and treat setup as complete. |
| Works outside but not at home | Set LAN DNS overrides for all four application names; clients may be bypassing router DNS. |
| LAN application returns 403 | Check actual client IPv4 and `LAN_CIDR`, DNS overrides, and whether a proxy is obscuring source addresses. Do not broaden the allowlist to `0.0.0.0/0`. |
| Internet application does not return 403 | Stop port forwards. Remove upstream proxy/CDN or router source NAT that makes WAN users appear local before restoring access. |
| WireGuard has no handshake | Check the `home` A record, `sudo journalctl -u den-ddns`, WAN IPv4/CGNAT, UDP 41873, mobile-data test, and `sudo wg show`. |
| VPN handshake but no app | Check profile DNS, local subnet overlap, `systemctl status den-dns`, client encrypted-DNS settings, and firewall forwarding rules. |
| Nextcloud stays unready | Read `sudo den logs nextcloud` and `sudo den logs nextcloud-db`; initial setup can be slow. Check disk space. |
| Media not found | Jellyfin sees `/media/...`, not the host `/srv/den/media/...`; UID 1000 must be able to read it. |
| Secondary storage is missing / Docker will not start | Verify `findmnt /mnt/den-storage`, `findmnt /srv/den/media` and `findmnt /srv/den/downloads` (use your configured mount path). Inspect `systemctl status srv-den-media.mount srv-den-downloads.mount docker` and the HDD UUID in `/etc/fstab`. Restore the disk/mounts, then start Docker and DEN; never remove storage dependencies just to start with empty SSD folders. |
| Backup fails | Check `mountpoint /mnt/den-backup`, available space, and `journalctl -u den-backup.service`. Never initialize a new repo to hide a password mismatch. |
| Another operation is running | Wait for backup/update/restore to finish; the shared lock prevents conflicting maintenance. |
| Monitoring failure banner | Run `sudo den check`; a successful check clears the banner. Read the failed unit journal before resetting failure state. |
| Update did not become healthy | Keep the pre-update snapshot and follow `backup.md`; do not downgrade images over migrated data. |
| Fluxer is unavailable | Run `sudo den fluxer-status`, `sudo rexctl --dir /opt/den/fluxer doctor`, and inspect `sudo rexctl --dir /opt/den/fluxer logs`. Check that the Traefik backend at `172.30.44.1:29461` is listening and the `chat` DNS override resolves to `LAN_IP`. |
| Fluxer voice does not connect | Confirm the client is on LAN or VPN, `LAN_IP` is advertised by Fluxer, and host TCP 7881/UDP 7882 are allowed. Do not solve this by forwarding voice ports from the WAN. |

If initial provisioning failed after `.env` was written, `sudo den start` can restart already prepared containers but cannot repair host steps that were never installed. Inspect `systemctl status docker wg-quick@wg0 den-dns den` and installed files to identify the missing step. Full automatic interrupted-install resume remains a known limitation.