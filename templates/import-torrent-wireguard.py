#!/usr/bin/env python3
import base64
import binascii
import ipaddress
import os
import re
import socket
import stat
import sys


class EndpointError(ValueError):
    pass


def resolve_endpoint(endpoint):
    labels = endpoint.rstrip(".").split(".")
    if len(endpoint) > 253 or len(labels) < 2 or not all(
        re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
        for label in labels
    ):
        raise EndpointError("Endpoint must be a public IPv4 address or valid provider hostname.")
    try:
        answers = socket.getaddrinfo(endpoint, None, socket.AF_INET, socket.SOCK_DGRAM)
    except socket.gaierror:
        raise EndpointError("Provider endpoint DNS lookup failed. Check DEN's DNS connection and retry the import.") from None
    addresses = [ipaddress.IPv4Address(answer[4][0]) for answer in answers]
    if not addresses or any(not address.is_global or address.is_multicast for address in addresses):
        raise EndpointError("Provider endpoint must resolve only to public IPv4 addresses.")
    return addresses[0]


def parse(text, lan):
    allowed = {
        "Interface": {"PrivateKey", "Address", "DNS", "MTU"},
        "Peer": {"PublicKey", "PresharedKey", "AllowedIPs", "Endpoint", "PersistentKeepalive"},
    }
    sections = {}
    section = None
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            if section not in allowed or section in sections:
                raise ValueError("Use one [Interface] and one [Peer] section.")
            sections[section] = {}
            continue
        key, separator, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or section is None or key not in allowed[section] or key in sections[section]:
            raise ValueError("Unsupported or duplicate profile option. Hooks, scripts and custom routing are not accepted.")
        sections[section][key] = value
    if set(sections) != set(allowed):
        raise ValueError("Use one [Interface] and one [Peer] section.")
    interface, peer = sections["Interface"], sections["Peer"]
    for values, key in ((interface, "PrivateKey"), (peer, "PublicKey")):
        check_key(values.get(key, ""))
    if "PresharedKey" in peer:
        check_key(peer["PresharedKey"])
    addresses = [ipaddress.ip_interface(value.strip()) for value in interface.get("Address", "").split(",")]
    ipv4 = [address for address in addresses if address.version == 4]
    if not ipv4:
        raise ValueError("A tunnel IPv4 address is required; IPv6-only profiles are not supported.")
    denied = [ipaddress.ip_network(value) for value in (lan, "10.44.0.0/24", "172.30.44.0/24")]
    if any(address.network.overlaps(subnet) for address in ipv4 for subnet in denied):
        raise ValueError("Tunnel address overlaps DEN's LAN, home VPN or container network. Request another provider profile.")
    routes = {ipaddress.ip_network(value.strip()) for value in peer.get("AllowedIPs", "").split(",")}
    if ipaddress.ip_network("0.0.0.0/0") not in routes:
        raise ValueError("A full-tunnel profile with AllowedIPs = 0.0.0.0/0 is required, not a DEN home-access profile.")
    endpoint, separator, port = peer.get("Endpoint", "").rpartition(":")
    if not separator or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError("Endpoint must be a numeric IPv4 address and UDP port.")
    try:
        endpoint_ip = ipaddress.IPv4Address(endpoint)
    except ipaddress.AddressValueError:
        endpoint_ip = resolve_endpoint(endpoint)
    if not endpoint_ip.is_global or endpoint_ip.is_multicast:
        raise ValueError("Endpoint must be a public VPN server IPv4 address.")
    if "DNS" in interface:
        for value in interface["DNS"].split(","):
            ipaddress.ip_address(value.strip())
    mtu = interface.get("MTU")
    if mtu is not None and (not mtu.isdecimal() or not 1280 <= int(mtu) <= 1420):
        raise ValueError("MTU must be between 1280 and 1420.")
    keepalive = peer.get("PersistentKeepalive")
    if keepalive is not None and (not keepalive.isdecimal() or not 0 <= int(keepalive) <= 65535):
        raise ValueError("Invalid PersistentKeepalive interval.")
    result = ["[Interface]", f"PrivateKey = {interface['PrivateKey']}",
              "Address = " + ", ".join(str(address) for address in ipv4)]
    if mtu:
        result.append(f"MTU = {mtu}")
    result += ["", "[Peer]", f"PublicKey = {peer['PublicKey']}"]
    if "PresharedKey" in peer:
        result.append(f"PresharedKey = {peer['PresharedKey']}")
    result += [f"Endpoint = {endpoint_ip}:{int(port)}", "AllowedIPs = 0.0.0.0/0"]
    if keepalive:
        result.append(f"PersistentKeepalive = {keepalive}")
    return "\n".join(result) + "\n"


def check_key(value):
    try:
        valid = len(base64.b64decode(value, validate=True)) == 32
    except (ValueError, binascii.Error):
        valid = False
    if not valid:
        raise ValueError("A WireGuard key is missing or invalid.")


if __name__ == "__main__":
    try:
        descriptor = os.open(sys.argv[1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "r", encoding="ascii") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > 16384 or info.st_mode & 0o077:
                raise ValueError("Choose an owner-only regular WireGuard profile of at most 16 KiB.")
            text = source.read(16385)
            if len(text) > 16384:
                raise ValueError("Profile is too large.")
            result = parse(text, sys.argv[2])
    except EndpointError as error:
        print(f"DEN: {error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, UnicodeError, ValueError):
        # Profile/parser errors can contain private keys; never print their values.
        print("DEN: Invalid WireGuard profile. Use chmod 600, one IPv4 full-tunnel provider profile, public IPv4 endpoint or provider hostname, "
              "valid keys and no hooks/custom routing. See docs/qbittorrent.md.", file=sys.stderr)
        sys.exit(1)
    print(result, end="")
