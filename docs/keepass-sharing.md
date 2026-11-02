# Password Vaults for a Household

Keep three different audiences separate:

| Vault | Contents | Access |
| --- | --- | --- |
| Owner/admin | DEN administrator, database, backup and VPN secrets | Server owner only |
| Family | Intentionally shared household credentials | Selected family members |
| Personal | Each person's private accounts | That person only |

Use different master passwords. Never give family members the DEN admin vault
just to share a streaming or household account. Create an empty family KDBX;
do not clone the admin vault and delete entries, since history can retain secrets.

## One canonical admin vault

With KeePass enabled, DEN stores the canonical file at
`/opt/den/vaults/admin/credentials.kdbx`. Its saved master password remains in
`/opt/den/private/keepass-master-password`, outside the vault directory.
Retrieve the password privately with `sudo den keepass-password`.

Older vaults under `private/credentials.kdbx` migrate on synchronization, keeping
a root-only `private/credentials.kdbx.pre-share` rollback copy. If both old and
new locations contain a vault, synchronization refuses to choose between them.
Existing export/password commands accept the old location until migration.
An existing rollback copy is never overwritten; reconcile it manually before
retrying a migration.

DEN adds missing entries without overwriting existing ones. Close KeePassXC
before `sudo den keepass-sync`, upgrades or profile creation. Synchronization
preserves database ownership, refuses a recognized lock file and checks for
concurrent changes before replacement. These are safeguards, not distributed
locking: coordinate writers and resolve save/reload conflicts explicitly.
Keep application passwords and saved vault entries consistent yourself.

## Optional direct access over LAN/VPN

An administrator can share **only** `vaults/admin/` using authenticated SMB3
encryption/signing and a dedicated owner account. Do not share `/opt/den`,
`private/`, saved master passwords or recovery kits. Directory separation makes
this possible without exposing the rest of the deployment.

This is a manual integration, not installed or enabled by DEN:

- Give the dedicated account access only to the vault directory and necessary
  parent traversal. Do not grant a shell, sudo or membership of the Docker group.
- Disable guest access and symlink following; require SMB3 encryption and
  signing. Keep vault files private to the dedicated account (mode `0600`).
- Restrict the listener and firewall to LAN/VPN. Never publicly forward SMB
  TCP 445 or NetBIOS ports.
- Keep SELinux enforcing on Fedora. A share needs a persistent Samba-compatible
  file context for its specific directory; configure that and source-restricted
  firewalld rules before access testing. Do not disable SELinux or open Samba
  broadly to solve permission errors.
- Install KeePassXC on the workstation. Open the KDBX directly from the mounted
  share, not as another downloaded working copy. Test save, close and reopen.
- Reconcile older local edits before retiring downloaded working copies.
  Recovery copies remain necessary, clearly marked as backups.

With DEN and BASM on one physical host, a share on the Fedora host and a share
on its Debian VM are separate services with different IPs and credentials.
Do not expose DEN owner secrets through a BASM employee/family share.

SMB prevents accidental independent working copies; it cannot prevent users
from retaining copies or reading decrypted entries in workstation memory.
An outage can block saves. Everyone with a shared vault's master password can
read every entry: KeePass does not offer per-entry family permissions or central
auditing. Rotate shared secrets when access changes; revoking a share account
does not revoke previously copied secrets.

## Family and personal vaults

Use a separate restricted share and individual share logins for a family KDBX.
Do not reuse the owner's share account or vault master password. Coordinate
edits; save/reload/merge explicitly rather than overwriting another person's work.

Each family member can keep a personal KDBX in their own private Nextcloud
account, accessed with their own app account rather than the DEN administrator.
Sync creates local copies and can create conflicts: close before switching
devices, and resolve conflicts. Personal storage is not direct server-file
editing. Keep recovery material outside the vault it is needed to unlock.

## Backup and recovery

DEN snapshots copy the deployment tree, including `vaults/admin/`, into the
encrypted backup. Keep an independent master-password copy: the Restic key is
itself inside the admin vault.
Recovery restores this vault directory alongside the private saved settings;
older snapshots containing only the legacy vault remain supported.

SMB account state, ACLs, SELinux contexts and firewall configuration are host
settings, not automatically recreated by `den` recovery. Save protected recovery
instructions/configuration separately, and test restoring them. Never publish
Samba password hashes, KDBX master passwords or private VPN attachments.
