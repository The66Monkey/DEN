#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
DEPLOY_DIR="$(mktemp -d)"
trap 'rm -rf "$DEPLOY_DIR"' EXIT
read_settings "$ROOT/config/example.env"
mkdir -p "$DEPLOY_DIR/templates"
mkdir -p "$DEPLOY_DIR/docs/images"
cp "$ROOT/docs/images/mascot.png" "$DEPLOY_DIR/docs/images/"
cp "$ROOT/templates/home.html" "$DEPLOY_DIR/templates/"
cp "$ROOT/README.md" "$DEPLOY_DIR/"
for fluxer in no yes; do
    for torrents in no yes; do
        FLUXER_ENABLED="$fluxer" QBITTORRENT_ENABLED="$torrents" write_homepage
        python3 - "$DEPLOY_DIR" "$DOMAIN" "$LAN_IP" "$fluxer" "$torrents" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

directory, domain, ip, fluxer, torrents = sys.argv[1:]
root = Path(directory)
page = (root / "home/index.html").read_text()

class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links = []
        self.text = []
        self.scripts = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a":
            self.links.append(attrs["href"])
        if tag == "script":
            self.scripts += 1

    def handle_data(self, data):
        self.text.append(data)

parsed = Page()
parsed.feed(page)
services = ["media", "photos", "files", "git"]
if fluxer == "yes":
    services.append("chat")
if torrents == "yes":
    services.append("downloads")
services.append("server")
expected_links = [f"https://{name}.{domain}/" for name in services]
if fluxer == "yes":
    expected_links.insert(services.index("chat") + 1, f"https://chat.{domain}/admin")
assert parsed.links == expected_links + ["https://github.com/The66Monkey/DEN"]
text = "".join(parsed.text)
assert ("Fluxer - Chat (public, invite-only)" in text) == (fluxer == "yes")
assert ("Fluxer - Administration" in text) == (fluxer == "yes")
assert "Welcome home to your DEN" in text
assert "Jellyfin - Media" in text
assert "Immich - Photos" in text
assert "Nextcloud - Files" in text
assert "Forgejo - Git" in text
assert 'class="service-mark mark-jellyfin" aria-hidden="true">J</span>' in page
assert 'class="service-mark mark-immich" aria-hidden="true">I</span>' in page
assert f"ssh YOUR-FEDORA-USER@{ip}" in text
assert "sudo grep '^NEXTCLOUD_ADMIN_PASSWORD=' /opt/den/.env" in text
assert "sudo den keepass-password" in text
assert "sudo den vpn-add DEVICE-NAME" in text
assert "Treat all outputs as private" in text
assert (root / "README.md").read_text() not in text
assert 'src="/mascot.png"' in page
assert (root / "home/mascot.png").read_bytes() == (root / "docs/images/mascot.png").read_bytes()
assert parsed.scripts == 0
assert "{{" not in page
assert (root / "home").stat().st_mode & 0o777 == 0o755
assert (root / "home/index.html").stat().st_mode & 0o777 == 0o644
PY
    done
    mkdir -p "$DEPLOY_DIR/private/infrastructure"
    touch "$DEPLOY_DIR/private/infrastructure/compose.yml"
    write_homepage
    if grep -Fq "https://dns.$DOMAIN/" "$DEPLOY_DIR/home/index.html"; then fail 'AdGuard link shown without the independent edge.'; fi
    touch "$DEPLOY_DIR/private/external-edge"
    write_homepage
    grep -Fq "https://dns.$DOMAIN/" "$DEPLOY_DIR/home/index.html"
    grep -Fq 'AdGuard Home - DNS' "$DEPLOY_DIR/home/index.html"
    rm "$DEPLOY_DIR/private/external-edge"
    write_homepage
    if grep -Fq "https://dns.$DOMAIN/" "$DEPLOY_DIR/home/index.html"; then fail 'Disabled infrastructure retained the AdGuard link.'; fi
done
printf '<script>alert("README")</script> & private text\n' > "$DEPLOY_DIR/README.md"
write_homepage
if grep -Fq '<script>' "$DEPLOY_DIR/home/index.html"; then fail 'README HTML leaked into homepage.'; fi
rm "$DEPLOY_DIR/README.md"
COCKPIT_ENABLED=no
write_homepage
if grep -Fq "https://server.$DOMAIN/" "$DEPLOY_DIR/home/index.html"; then fail 'Opt-out retained Cockpit link.'; fi
write_homepage
printf '{"title":"DEN+ functions","features":[{"label":"AI <chat>","description":"Local & private","enabled":true,"url":"https://ai.home.example.net/"},{"label":"LAMP","description":"Not enabled","enabled":false,"url":"https://lamp.home.example.net/"}]}\n' > "$DEPLOY_DIR/private/home-addon.json"
write_homepage
grep -Fq 'DEN+ functions' "$DEPLOY_DIR/home/index.html"
grep -Fq 'https://ai.home.example.net/' "$DEPLOY_DIR/home/index.html"
grep -Fq 'AI &lt;chat&gt;' "$DEPLOY_DIR/home/index.html"
grep -Fq 'Local &amp; private' "$DEPLOY_DIR/home/index.html"
grep -Fq 'Other features (not enabled)' "$DEPLOY_DIR/home/index.html"
! grep -Fq 'href="https://lamp.' "$DEPLOY_DIR/home/index.html"
printf '{"title":"bad","features":[{"label":"bad","description":"","enabled":true,"url":"javascript:alert(1)"}]}\n' > "$DEPLOY_DIR/private/home-addon.json"
if write_homepage 2>/dev/null; then fail 'Accepted invalid homepage URL.'; fi
printf 'not json\n' > "$DEPLOY_DIR/private/home-addon.json"
if write_homepage 2>/dev/null; then fail 'Accepted invalid homepage manifest.'; fi
rm "$DEPLOY_DIR/private/home-addon.json"
rm "$DEPLOY_DIR/docs/images/mascot.png"
if write_homepage 2>/dev/null; then fail 'Missing mascot returned success.'; fi
printf 'Homepage mascot, GitHub link, SSH instructions, optional links and generation errors passed.\n'
