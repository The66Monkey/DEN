# Your First Evening

Use the service names printed by `sudo den status`, replacing examples below with your domain.

## Watch Something

Open Jellyfin at `https://media.your-domain`. Create its initial administrator, then add libraries using `/media/movies`, `/media/tv`, and `/media/music` inside the container. Your server's matching folders are `/srv/den/media/movies`, `/srv/den/media/tv`, and `/srv/den/media/music`.

Copy media you own into those folders using your existing SSH/SFTP client. Ensure UID 1000 can read directories and files; DEN gives the initial media folders to UID 1000. The media mount is read-only in Jellyfin. Choose clients that can direct-play your files; DEN does not configure GPU acceleration or automatic downloading tools.

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

## Finish Safely

Import a VPN profile onto your phone and test from mobile data. Then:

```bash
sudo den backup
sudo den snapshots
sudo den check
```

Save the external recovery kit and run a staged restore as described in [backup and recovery](backup.md). Only then start depending on DEN for important data.