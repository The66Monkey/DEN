#!/usr/bin/env python3

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from pykeepass import PyKeePass


def main():
    root = Path(__file__).resolve().parents[1]
    helper = root / "templates" / "keepass-sync.py"
    with tempfile.TemporaryDirectory() as temporary_directory:
        deployment = Path(temporary_directory)
        private = deployment / "private"
        private.mkdir(mode=0o700)
        (deployment / ".env").write_text(
            "DOMAIN=home.example.net\n"
            "BACKUP_MOUNT=/mnt/den-backup\n"
            "DB_PASSWORD=db-secret\n"
            "NEXTCLOUD_ADMIN_PASSWORD=cloud-secret\n"
            "RESTIC_PASSWORD=restic-secret\n"
        )
        (private / "wg0.conf").write_text("[Interface]\nPrivateKey = server-key\n")
        (private / "home.conf").write_text("[Interface]\nPrivateKey = client-key\n")

        subprocess.run([sys.executable, str(helper), str(deployment)], check=True)
        database = deployment / "vaults/admin/credentials.kdbx"
        master_file = private / "keepass-master-password"
        assert os.stat(private).st_mode & 0o777 == 0o700
        assert os.stat(database).st_mode & 0o777 == 0o600
        assert os.stat(master_file).st_mode & 0o777 == 0o600
        master = master_file.read_text().strip()

        vault = PyKeePass(database, password=master)
        generated = vault.find_groups(name="Generated", first=True)
        assert generated is not None
        assert vault.find_entries(title="Nextcloud administrator", group=generated, first=True).password == "cloud-secret"
        assert vault.find_entries(title="Restic backup encryption", group=generated, first=True).password == "restic-secret"
        assert vault.find_entries(title="WireGuard wg0", group=generated, first=True).attachments[0].filename == "wg0.conf"

        database_entry = vault.find_entries(title="Application database password", group=generated, first=True)
        database_entry.password = "changed-in-KeePassXC"
        vault.add_entry(vault.root_group, "Personal entry", "user", "keep-me")
        vault.save()
        (private / "tablet.conf").write_text("[Interface]\nPrivateKey = tablet-key\n")

        subprocess.run([sys.executable, str(helper), str(deployment)], check=True)
        vault = PyKeePass(database, password=master)
        generated = vault.find_groups(name="Generated", first=True)
        assert vault.find_entries(title="Application database password", group=generated, first=True).password == "changed-in-KeePassXC"
        assert len(vault.find_entries(title="Application database password", group=generated)) == 1
        assert vault.find_entries(title="WireGuard tablet", group=generated, first=True).attachments[0].filename == "tablet.conf"
        assert vault.find_entries(title="Personal entry", first=True).password == "keep-me"

        before = database.read_bytes()
        lock = database.with_name(database.name + ".lock")
        lock.touch()
        result = subprocess.run([sys.executable, str(helper), str(deployment)], capture_output=True)
        assert result.returncode != 0
        assert database.read_bytes() == before
        lock.unlink()

        # Older deployments migrate once and retain a private rollback copy.
        legacy = private / "credentials.kdbx"
        database.rename(legacy)
        subprocess.run([sys.executable, str(helper), str(deployment)], check=True)
        assert database.is_file() and not legacy.exists()
        assert (private / "credentials.kdbx.pre-share").read_bytes() == before

        legacy.write_bytes(database.read_bytes())
        before = database.read_bytes()
        result = subprocess.run([sys.executable, str(helper), str(deployment)], capture_output=True)
        assert result.returncode != 0
        assert database.read_bytes() == before
        legacy.unlink()

        database.rename(legacy)
        backup = private / "credentials.kdbx.pre-share"
        saved_backup = backup.read_bytes()
        result = subprocess.run([sys.executable, str(helper), str(deployment)], capture_output=True)
        assert result.returncode != 0
        assert legacy.read_bytes() == before and not database.exists()
        assert backup.read_bytes() == saved_backup
        legacy.rename(database)

        # File replacements must retain a dedicated share account's ownership.
        if os.geteuid() == 0:
            os.chown(database, 65534, 65534)
            subprocess.run([sys.executable, str(helper), str(deployment)], check=True)
            assert (database.stat().st_uid, database.stat().st_gid) == (65534, 65534)


if __name__ == "__main__":
    main()