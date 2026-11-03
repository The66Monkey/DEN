import base64
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

if os.environ.get("DEN_ISOLATED_COCKPIT_TEST") != "yes":
    raise SystemExit("Run only inside an isolated mount/network namespace.")

root = Path(__file__).resolve().parents[1]
subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
with tempfile.TemporaryDirectory() as directory:
    cockpit = Path(directory) / "cockpit"
    cockpit.mkdir()
    config = subprocess.run(
        ["python3", str(root / "templates/configure-cockpit.py"),
         str(cockpit / "absent.conf"), "home.example.net"],
        check=True, capture_output=True, text=True,
    ).stdout
    (cockpit / "cockpit.conf").write_text(config)
    environment = dict(os.environ, XDG_CONFIG_DIRS=directory)
    process = subprocess.Popen(
        ["/usr/libexec/cockpit-ws", "--no-tls", "--address=127.0.0.1", "--port=19090"],
        env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        for attempt in range(50):
            if process.poll() is not None:
                raise AssertionError(process.stdout.read())
            try:
                with socket.create_connection(("127.0.0.1", 19090), timeout=0.1):
                    break
            except ConnectionRefusedError:
                time.sleep(0.1)
        else:
            raise AssertionError("Cockpit did not start")

        def request(path, origin=None):
            headers = [
                f"GET {path} HTTP/1.1", "Host: server.home.example.net",
                "X-Forwarded-Proto: https",
            ]
            if origin:
                headers += [
                    "Connection: Upgrade", "Upgrade: websocket",
                    "Sec-WebSocket-Version: 13", "Sec-WebSocket-Protocol: cockpit1",
                    "Sec-WebSocket-Key: " + base64.b64encode(os.urandom(16)).decode(),
                    f"Origin: {origin}",
                ]
            else:
                headers.append("Connection: close")
            with socket.create_connection(("127.0.0.1", 19090), timeout=3) as connection:
                connection.sendall(("\r\n".join(headers) + "\r\n\r\n").encode())
                return connection.recv(8192).split(b"\r\n", 1)[0]

        assert b"200" in request("/")
        assert b"101" in request("/cockpit/socket", "https://server.home.example.net")
        assert b"403" in request("/cockpit/socket", "https://other.example.net")
        print("Real Cockpit login page and WebSocket origin checks passed.")
    finally:
        process.terminate()
        process.communicate(timeout=10)
