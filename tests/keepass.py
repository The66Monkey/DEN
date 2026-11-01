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
        database = private / "credentials.kdbx"
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


if __name__ == "__main__":
    main()