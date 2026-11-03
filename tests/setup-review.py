#!/usr/bin/env python3
"""Exercise setup review in a real terminal without touching host services."""
import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
COMMAND = '''
source "$1/lib/core.sh"
check_host() { printf 'HOST-CHECK:%s\\n' "$DOMAIN"; }
prepare_installation "$2"
printf 'ACCEPTED:%s:%s\\n' "$DOMAIN" "$SERVER_HOSTNAME"
'''


def interactive(settings, actions, term="xterm"):
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ["bash", "-c", COMMAND, "bash", str(ROOT), str(settings)],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": term},
    )
    os.close(slave)
    output = bytearray()
    pending = bytearray()
    deadline = time.monotonic() + 15
    try:
        while True:
            if time.monotonic() >= deadline:
                raise AssertionError(f"Setup review timed out: {output.decode()}")
            if not select.select([master], [], [], 0.1)[0]:
                continue
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not data:
                break
            output.extend(data)
            pending.extend(data)
            while actions and actions[0][0].encode() in pending:
                prompt, answer, update = actions.pop(0)
                end = pending.index(prompt.encode()) + len(prompt.encode())
                del pending[:end]
                if update:
                    update()
                os.write(master, answer)
        assert not actions, f"Missing prompts: {actions}; output: {output.decode()}"
        return process.wait(timeout=5), output.decode()
    finally:
        os.close(master)
        if process.poll() is None:
            process.kill()
        process.wait()


with tempfile.TemporaryDirectory() as temporary:
    settings = Path(temporary, "den.env")
    original = (ROOT / "config/example.env").read_text()
    settings.write_text(original)
    hostname_prompt = "Server hostname (one label)"
    confirm_prompt = "Accept and install (A), restart review (R), or cancel (C):"

    def update_settings():
        settings.write_text(original.replace("home.example.net", "revised.example.net"))

    status, output = interactive(settings, [
        (hostname_prompt, b"FirstHost\n", None),
        (confirm_prompt, b"\n", None),
        (confirm_prompt, b"invalid\n", None),
        (confirm_prompt, b"R\n", None),
        ("Press Enter to reload the settings and repeat host checks:", b"\n", update_settings),
        (hostname_prompt, b"FinalHost\n", None),
        (confirm_prompt, b"A\n", None),
    ])
    assert status == 0, output
    assert "ACCEPTED:revised.example.net:FinalHost" in output
    assert output.count("Review DEN setup") == 2
    assert output.count("Enter A to accept") == 2
    assert "HOST-CHECK:home.example.net" in output
    assert "HOST-CHECK:revised.example.net" in output
    assert "\033[H\033[2J" in output

    for answer, expected in [(b"C\n", 0), (b"\x04", 1)]:
        status, output = interactive(settings, [
            (hostname_prompt, b"\n", None),
            (confirm_prompt, answer, None),
        ], term="dumb")
        assert status == expected, output
        assert "ACCEPTED:" not in output
        assert "\033" not in output

    # Restart must revalidate changed settings instead of accepting an invalid plan.
    status, output = interactive(settings, [
        (hostname_prompt, b"\n", None),
        (confirm_prompt, b"R\n", None),
        ("Press Enter to reload the settings and repeat host checks:", b"\n",
         lambda: settings.write_text("UNKNOWN=value\n")),
    ])
    assert status != 0 and "Unknown config key" in output
    assert "ACCEPTED:" not in output

    private_password = "0123456789abcdef" * 3
    settings.write_text(original + f"\nDB_PASSWORD={private_password}\n")
    result = subprocess.run(
        ["bash", "-c", COMMAND, "bash", str(ROOT), str(settings)],
        input="", capture_output=True, text=True, check=True,
    )
    assert "Non-interactive installation: continuing" in result.stdout
    assert "Review DEN setup" in result.stdout and "ACCEPTED:" in result.stdout
    assert private_password not in result.stdout + result.stderr
    assert "\033" not in result.stdout
    assert confirm_prompt not in result.stdout + result.stderr

    enabled = original.replace("MEDIA_MOUNT=/mnt/den-storage", "MEDIA_MOUNT=/mnt/den-backup")
    for key in ("ALLOW_SHARED_MEDIA_BACKUP", "KEEPASS_ENABLED", "FLUXER_ENABLED",
                "QBITTORRENT_ENABLED", "AI_ENABLED"):
        enabled = enabled.replace(f"{key}=no", f"{key}=yes")
    for protected in ("no", "yes"):
        settings.write_text(enabled.replace(
            "QBITTORRENT_VPN_ENABLED=no", f"QBITTORRENT_VPN_ENABLED={protected}",
        ))
        result = subprocess.run(
            ["bash", "-c", COMMAND, "bash", str(ROOT), str(settings)],
            input="", capture_output=True, text=True, check=True,
        )
        assert "WARNING: shared media/backup storage" in result.stdout
        assert "PUBLIC chat/calls" in result.stdout
        assert "AI model: llama3.2:3b" in result.stdout
        expected = ("downloads stay blocked" if protected == "yes"
                    else "trackers and peers see your normal public IP")
        assert expected in result.stdout

print("DEN terminal review, restart validation, cancel, EOF and unattended checks passed.")
