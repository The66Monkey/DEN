# Your First Evening

Use the service names printed by `sudo den status`, replacing examples below with your domain.

## Watch Something

Open Jellyfin at `https://media.your-domain`. Create its initial administrator, then add libraries using `/media/movies`, `/media/tv`, and `/media/music` inside the container. Your server's matching folders are `/srv/den/media/movies`, `/srv/den/media/tv`, and `/srv/den/media/music`.

Copy media you own into those folders using your existing SSH/SFTP client. Ensure UID 1000 can read directories and files; DEN gives the initial media folders to UID 1000. The media mount is read-only in Jellyfin. Choose clients that can direct-play your files; DEN does not configure GPU acceleration or automatic downloading tools.

With the default secondary-storage setting, those host folders are bind mounts
of `/mnt/den-storage/den/media` on the larger HDD. Keep using the same library
paths. The Jellyfin setup wizard runs in your own computer/phone's browser;
Fedora Server itself needs no GUI.

Finish the setup wizard before giving anyone else LAN/VPN access. Create separate household accounts rather than sharing the administrator login.

## Put Photos Somewhere Safe

Open Immich at `https://photos.your-domain`. Create the first administrator and household users, then connect the Immich mobile app and enable photo upload. Check that several test uploads appear and can be downloaded again. Facial recognition and initial library processing can be slow on an old PC.

An upload or sync is **not** a backup. Keep originals elsewhere until you have tested DEN's encrypted backup and restore.

## Sync Files

Open Nextcloud at `https://files.your-domain`. The initial username is `admin`. Read its generated password privately on the server:

```bash
sudo grep '^NEXTCLOUD_ADMIN_PASSWORD=' /opt/den/.env
```

Create a separate account for each family member and use those accounts with the Nextcloud desktop/mobile apps. Upload a small file and download it on a second device. Use Nextcloud, not direct edits to `/srv/den/nextcloud/html/data`, for managed files. Local household shares work; people outside the LAN need VPN. Email sending is not configured, so password resets are handled by the administrator.

## Keep a Project

Create the Forgejo administrator:

```bash
sudo den git-admin
```

Open `https://git.your-domain`. Create your account/repository and a personal access token for Git over HTTPS. Public registration, SSH Git, and Actions runners are disabled. You can create other users from the administrator interface. Code editors and build tools stay on your own computer.

## Optional Fluxer Chat

When Fluxer is enabled, use the browser setup token printed by the installer at `https://chat.your-domain` to create the first administrator. Retrieve the token again privately with `sudo rexctl --dir /opt/den/fluxer setup token`. Choose the instance name and sign-in options in the browser; installation does not pass terminal-only setup flags to browser setup. Registration is invite-only; create invitations with `sudo rexctl --dir /opt/den/fluxer invites create`. Chat and calls are available only from the LAN or VPN by default.

## Finish Safely

### Connect Your Phone with WireGuard

DEN installs `qrencode` as standard so you can scan a VPN profile instead of
copying it by hand. Install the WireGuard app on your phone. From a computer
on your home network, SSH into the server using your Fedora login:

```bash
ssh YOUR-FEDORA-USER@SERVER-LAN-IP
```

In that SSH session, create a separate profile for your phone and display it:

```bash
sudo den vpn-add phone
sudo sh -c 'qrencode -t ansiutf8 < /opt/den/private/phone.conf'
```

If `phone` already exists, skip `vpn-add` and just show its QR code. In the
phone app, choose **Add tunnel / Scan from QR code** and scan your computer's
terminal. Use a different profile name for each additional device.

The QR code contains the VPN private key. Do not share it, post screenshots,
or scan the same profile onto multiple devices. Revoke a lost device with
`sudo den vpn-remove phone`.

Forward UDP 41873 to the server's LAN IP. Turn off phone Wi-Fi, enable the
WireGuard tunnel and open the application URLs on mobile data. The profile
provides DEN's private DNS; device Private DNS or browser Secure DNS must not
bypass it. In DNS-01 VPN-only mode, leave any other server's TCP 80/443 forwards
unchanged.

### Back Up After Setup

After testing access from your phone:

```bash
sudo den backup
sudo den snapshots
sudo den check
```

Save the external recovery kit and run a staged restore as described in [backup and recovery](backup.md). Only then start depending on DEN for important data.