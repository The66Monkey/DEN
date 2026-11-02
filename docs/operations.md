# Keep DEN Running

Most maintenance is automatic. Connect over SSH when you need to check something:

```bash
sudo den status
sudo den check
sudo den logs nextcloud      # replace with the service you need
```

DEN checks health hourly. Problems appear in the system journal and may show
on SSH login; there are no email or phone alerts.
If another operation is running, wait for it to finish.

## Automatic Monthly Maintenance

On the first of each month, between 04:00 and 04:30 server time, DEN updates
itself, enabled Fluxer and Fedora. It takes backups and may reboot.
Keep the storage disk connected. Missed maintenance runs when the timer resumes.

**Fluxer exposure change:** applying the public-chat update to an enabled
Fluxer install makes chat/calls public and resets voice IP discovery. Review
[direct router forwarding and cutover](networking.md#public-chat-and-calls)
before updating; DEN does not migrate an existing BASM instance.

Check the schedule or recent results:

```bash
systemctl list-timers den-update.timer
journalctl -u den-update.service -n 50
```

To run it now:

```bash
sudo den auto-update
```

To disable automatic updates:

```bash
sudo systemctl mask --now den-update.timer
```

To enable them again:

```bash
sudo systemctl unmask den-update.timer
sudo systemctl enable --now den-update.timer
```

For a different schedule, use `sudo systemctl edit den-update.timer`:

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-15 04:00:00
```

Then run `sudo systemctl daemon-reload` and
`sudo systemctl restart den-update.timer`.

Update failures stop the job. See [troubleshooting](troubleshooting.md);
do not remove an `update-in-progress` marker just to retry.

## Stop Without Losing Data

```bash
sudo systemctl stop den-update.timer den-backup.timer den-check.timer den.service
sudo den stop
```

WireGuard stays available. To resume:

```bash
sudo systemctl start den.service den-backup.timer den-check.timer den-update.timer
```

Do not delete data folders or Docker volumes to fix an error.
For disk space and saved snapshots, see [backup and recovery](backup.md).
Release maintainers: see [update contracts](architecture.md#release-updates).
