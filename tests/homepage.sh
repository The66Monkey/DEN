#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
DEPLOY_DIR="$(mktemp -d)"
trap 'rm -rf "$DEPLOY_DIR"' EXIT
read_settings "$ROOT/config/example.env"
mkdir -p "$DEPLOY_DIR/templates"
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
assert parsed.links == [f"https://{name}.{domain}/" for name in services]
text = "".join(parsed.text)
assert f"ssh YOUR-FEDORA-USER@{ip}" in text
assert (root / "README.md").read_text() in text
assert parsed.scripts == 0
assert "{{" not in page
assert (root / "home").stat().st_mode & 0o777 == 0o755
assert (root / "home/index.html").stat().st_mode & 0o777 == 0o644
PY
    done
done
printf '<script>alert("README")</script> & private text\n' > "$DEPLOY_DIR/README.md"
write_homepage
grep -Fq '&lt;script&gt;alert(&quot;README&quot;)&lt;/script&gt; &amp; private text' "$DEPLOY_DIR/home/index.html"
if grep -Fq '<script>' "$DEPLOY_DIR/home/index.html"; then fail 'README HTML was not escaped.'; fi
rm "$DEPLOY_DIR/README.md"
if write_homepage 2>/dev/null; then fail 'Missing README returned success.'; fi
printf 'Homepage README, SSH instructions, optional links, escaping and generation errors passed.\n'
