#!/usr/bin/env python3

import os
from pathlib import Path
import secrets
import sys
import tempfile

from pykeepass import PyKeePass, create_database


def read_environment(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator:
            raise ValueError("Invalid DEN environment file")
        values[key] = value
    return values


def create_master_file(path):
    password = secrets.token_urlsafe(32)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as output:
        output.write(password + "\n")


def add_entry(vault, group, title, username="", password="", url="", notes=""):
    entry = vault.find_entries(title=title, group=group, first=True)
    if entry is None:
        return vault.add_entry(group, title, username, password, url=url, notes=notes)
    return entry


def sync(deployment):
    private = deployment / "private"
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(private, 0o700)
    vault_directory = deployment / "vaults" / "admin"
    if vault_directory.is_symlink() or (deployment / "vaults").is_symlink():
        raise ValueError("Symlink vault directories are not supported")
    vault_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    database = vault_directory / "credentials.kdbx"
    legacy_database = private / "credentials.kdbx"
    master_file = private / "keepass-master-password"
    if database.is_symlink() or legacy_database.is_symlink() or master_file.is_symlink():
        raise ValueError("Symlink credential files are not supported")
    if (database.exists() or legacy_database.exists()) and not master_file.exists():
        raise ValueError("Existing database has no saved master password")
    if legacy_database.exists():
        if legacy_database.with_name(legacy_database.name + ".lock").exists():
            raise ValueError("Close the legacy KeePass database before migration")
        if database.exists():
            raise ValueError("Both legacy and admin databases exist; resolve manually")
        descriptor = os.open(private / "credentials.kdbx.pre-share",
                             os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(legacy_database.read_bytes())
        legacy_database.rename(database)
    if not master_file.exists():
        try:
            create_master_file(master_file)
        except FileExistsError:
            pass
    os.chmod(master_file, 0o600)
    master = master_file.read_text().rstrip("\n")
    if not master:
        raise ValueError("Empty master password")
    lock_file = database.with_name(database.name + ".lock")
    if lock_file.exists():
        raise ValueError("Close KeePassXC before updating the admin vault")
    original = database.read_bytes() if database.exists() else None
    owner = database.stat() if database.exists() else None

    values = read_environment(deployment / ".env")
    descriptor, temporary_name = tempfile.mkstemp(prefix=".credentials-", suffix=".kdbx", dir=vault_directory)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        vault = PyKeePass(database, password=master) if database.exists() else create_database(temporary, password=master)
        root_group = vault.find_groups(name="DEN", first=True)
        if root_group is None:
            root_group = vault.add_group(vault.root_group, "DEN")
        group = vault.find_groups(name="Generated", group=root_group, first=True)
        if group is None:
            group = vault.add_group(root_group, "Generated")

        domain = values["DOMAIN"]
        add_entry(vault, group, "Nextcloud administrator", "admin", values["NEXTCLOUD_ADMIN_PASSWORD"], f"https://files.{domain}")
        add_entry(vault, group, "Application database password", "", values["DB_PASSWORD"], notes="Shared by the DEN-managed application databases.")
        add_entry(vault, group, "Restic backup encryption", "", values["RESTIC_PASSWORD"], notes=f"Repository: {values['BACKUP_MOUNT']}/den-restic")

        for path in sorted(private.glob("*.conf")):
            if path.name == "dnsmasq.conf":
                continue
            title = f"WireGuard {path.stem}"
            entry = add_entry(vault, group, title, notes="Private WireGuard configuration attached.")
            if not any(attachment.filename == path.name for attachment in entry.attachments):
                binary = vault.add_binary(path.read_bytes())
                entry.add_attachment(binary, path.name)

        vault.save(temporary)
        os.chmod(temporary, 0o600)
        if owner is not None and (temporary.stat().st_uid, temporary.stat().st_gid) != (owner.st_uid, owner.st_gid):
            os.chown(temporary, owner.st_uid, owner.st_gid)
        if lock_file.exists() or (database.read_bytes() if database.exists() else None) != original:
            raise ValueError("Admin vault changed during synchronization; retry after closing KeePassXC")
        os.replace(temporary, database)
    finally:
        temporary.unlink(missing_ok=True)
    os.chmod(database, 0o600)
    print(f"KeePass vault synchronized at {database}")


if __name__ == "__main__":
    try:
        sync(Path(sys.argv[1]))
    except Exception:
        print("KeePass synchronization failed; check the protected vault and DEN environment.", file=sys.stderr)
        sys.exit(1)