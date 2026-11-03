import subprocess
import sys


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def ip(*args):
    return run("ip", *args)


SERVER = r"""
import socket
import threading

def serve(sock, udp):
    while True:
        if udp:
            data, address = sock.recvfrom(1024)
            sock.sendto(data, address)
        else:
            client, _ = sock.accept()
            client.sendall(b"ok")
            client.close()

for family, address in [(socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")]:
    for port in [22, 53, 80, 443, 9090, 7881, 18443, 18427]:
        sock = socket.socket(family, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if family == socket.AF_INET6:
            sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        sock.bind((address, port))
        sock.listen()
        threading.Thread(target=serve, args=(sock, False), daemon=True).start()
for port in [41873, 7882, 53]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", port))
    threading.Thread(target=serve, args=(sock, True), daemon=True).start()
print("ready", flush=True)
threading.Event().wait()
"""

CLIENT = r"""
import socket
import sys
source, target, port, protocol, expected = sys.argv[1:]
family = socket.AF_INET6 if ":" in target else socket.AF_INET
kind = socket.SOCK_DGRAM if protocol == "udp" else socket.SOCK_STREAM
with socket.socket(family, kind) as sock:
    sock.settimeout(0.7)
    sock.bind((source, 0))
    try:
        if protocol == "udp":
            sock.sendto(b"ok", (target, int(port)))
            response = sock.recv(32)
        else:
            sock.connect((target, int(port)))
            response = sock.recv(32)
        actual = response == b"ok"
    except socket.timeout:
        actual = False
assert actual == (expected == "allow"), (source, target, port, protocol, expected)
"""

processes = []
namespaces = ["den-client", "den-backend", "den-vpn-client"]
try:
    for namespace in namespaces:
        ip("netns", "add", namespace)
        ip("-n", namespace, "link", "set", "lo", "up")
    for host, peer, namespace, host_address, peer_address in [
        ("lan0", "client0", "den-client", "192.168.50.58/24", "192.168.50.20/24"),
        ("br-den-test", "backend0", "den-backend", "172.30.44.1/24", "172.30.44.2/24"),
        ("wg0", "vpn0", "den-vpn-client", "10.44.0.1/24", "10.44.0.2/24"),
    ]:
        ip("link", "add", host, "type", "veth", "peer", "name", peer)
        ip("link", "set", peer, "netns", namespace)
        ip("address", "add", host_address, "dev", host)
        ip("link", "set", host, "up")
        ip("-n", namespace, "address", "add", peer_address, "dev", peer)
        ip("-n", namespace, "link", "set", peer, "up")
        ip("-n", namespace, "route", "add", "default", "via", host_address.split("/")[0])
    ip("route", "add", "198.51.100.20/32", "dev", "lan0")
    ip("-n", "den-client", "address", "add", "198.51.100.20/32", "dev", "client0")
    ip("route", "add", "192.168.60.201/32", "dev", "lan0")
    ip("-n", "den-client", "address", "add", "192.168.60.201/32", "dev", "client0")
    ip("address", "add", "fd00:50::58/64", "dev", "lan0", "nodad")
    ip("-n", "den-client", "address", "add", "fd00:50::20/64", "dev", "client0", "nodad")
    run("sysctl", "-qw", "net.ipv4.ip_forward=1")
    run("nft", "-f", sys.argv[1])
    run("nft", "-f", sys.argv[1])
    run("nft", "-f", "-", input="""table ip den_test_nat {
        chain prerouting {
            type nat hook prerouting priority -100;
            ip daddr 192.168.50.58 tcp dport 443 dnat to 172.30.44.2:18443
        }
    }""")
    for prefix in [[], ["ip", "netns", "exec", "den-backend"]]:
        process = subprocess.Popen(
            [*prefix, "python3", "-u", "-c", SERVER],
            stdout=subprocess.PIPE,
            text=True,
        )
        processes.append(process)
        assert process.stdout.readline().strip() == "ready"

    def check(namespace, source, target, port, protocol="tcp", expected="allow"):
        run("ip", "netns", "exec", namespace, "python3", "-c", CLIENT,
            source, target, str(port), protocol, expected)

    for port in [22, 80, 443, 9090, 7881, 18427]:
        check("den-client", "192.168.50.20", "192.168.50.58", port)
        check("den-client", "198.51.100.20", "192.168.50.58", port,
              expected="allow" if port in [443, 7881] else "deny")
        check("den-client", "fd00:50::20", "fd00:50::58", port, expected="deny")
    check("den-client", "198.51.100.20", "192.168.50.58", 41873, "udp")
    check("den-client", "192.168.50.20", "192.168.50.58", 7882, "udp")
    check("den-client", "198.51.100.20", "192.168.50.58", 7882, "udp")
    for port in [53, 18427]:
        check("den-client", "198.51.100.20", "192.168.50.58", port, "udp", "deny")
    check("den-client", "198.51.100.20", "10.44.0.1", 7881, expected="deny")
    for port in [22, 80, 443, 9090, 7881]:
        check("den-vpn-client", "10.44.0.2", "192.168.50.58", port)
    check("den-vpn-client", "10.44.0.2", "10.44.0.1", 53, "udp")
    check("den-vpn-client", "10.44.0.2", "192.168.50.58", 7882, "udp")
    check("den-vpn-client", "10.44.0.2", "192.168.50.58", 18427, expected="deny")
    run("nft", "-f", sys.argv[2])
    check("den-client", "198.51.100.20", "192.168.50.58", 80)
    check("den-client", "198.51.100.20", "192.168.50.58", 443)
    run("nft", "-f", sys.argv[3])
    for port in [80, 443, 7881]:
        check("den-client", "198.51.100.20", "192.168.50.58", port, expected="deny")
    check("den-client", "198.51.100.20", "192.168.50.58", 7882, "udp", "deny")
    run("nft", "-f", sys.argv[4])
    for port in [22, 53, 80, 443, 9090, 7881, 18427]:
        check("den-client", "192.168.60.201", "192.168.50.58", port,
              expected="allow" if port in [53, 443] else "deny")
    for port in [53, 41873, 7882]:
        check("den-client", "192.168.60.201", "192.168.50.58", port, "udp",
              expected="allow" if port == 53 else "deny")
    check("den-client", "192.168.60.201", "172.30.44.2", 18443, expected="deny")
    check("den-client", "192.168.60.201", "10.44.0.1", 53, "udp", "deny")
    check("den-client", "fd00:50::20", "fd00:50::58", 443, expected="deny")
    # Disabling the option revokes TV access even when the edge remains public.
    run("nft", "-f", sys.argv[1])
    check("den-client", "192.168.60.201", "192.168.50.58", 53, "udp", "deny")
    print("Real LAN/VPN/WAN filtering, IPv6 denial, UDP entry and pre-DNAT protection passed.")
finally:
    for process in processes:
        process.terminate()
        process.wait(timeout=10)
    for namespace in namespaces:
        ip("netns", "del", namespace)
