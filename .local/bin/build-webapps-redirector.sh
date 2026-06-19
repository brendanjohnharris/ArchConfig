#!/usr/bin/env bash
# Build the self-contained "external links -> Firefox" redirector for the Chromium
# web-app SSBs. Produces:
#   * an unpacked MV3 extension (~/.local/share/webapps-chromium-ext) that intercepts
#     clicks on external http(s) links and hands them to a native host;
#   * a native messaging host (~/.local/bin/webapps-ff-open) that launches Firefox;
#   * the host manifest in Chromium's native-messaging dir, locked to the extension ID.
# A fixed RSA key gives the extension a DETERMINISTIC id, so allowed_origins matches.
# Links to each app's own domain (and auth domains) stay in-app; everything else -> Firefox.
# mailto:/vscode:/etc. are left untouched so Chromium's xdg delegation still opens native apps.
set -euo pipefail

EXTDIR="$HOME/.local/share/webapps-chromium-ext"
KEYFILE="$HOME/.local/share/webapps-chromium-ext.key"   # private key -> stable ext id (do NOT track)
HOST_NAME="org.fathom.ff_open"
HOST_SCRIPT="$HOME/.local/bin/webapps-ff-open"
# Chromium looks for native-messaging host manifests under <user-data-dir>/NativeMessagingHosts.
# The SSBs use --user-data-dir=~/.local/share/webapps-chromium, so install it there (and also
# in the default config dir as a belt-and-suspenders).
NM_DIRS=("$HOME/.local/share/webapps-chromium/NativeMessagingHosts" "$HOME/.config/chromium/NativeMessagingHosts")
MANIFEST="$HOME/.config/webapps/apps.tsv"

mkdir -p "$EXTDIR" "${NM_DIRS[@]}" "$(dirname "$HOST_SCRIPT")"

# 1. Stable key -> deterministic extension ID (id = a-p mapping of SHA256(pubkey DER)[:16]).
[ -f "$KEYFILE" ] || openssl genrsa -out "$KEYFILE" 2048 >/dev/null 2>&1
PUBKEY_B64="$(openssl rsa -in "$KEYFILE" -pubout -outform DER 2>/dev/null | openssl base64 -A)"
EXT_ID="$(python3 - "$PUBKEY_B64" <<'PY'
import sys, hashlib, base64
der = base64.b64decode(sys.argv[1])
h = hashlib.sha256(der).hexdigest()[:32]
print("".join(chr(ord("a") + int(c, 16)) for c in h))
PY
)"

# 2. Allowlist of hostnames to KEEP in-app: every app domain in apps.tsv + auth domains.
ALLOW_JSON="$(python3 - "$MANIFEST" <<'PY'
import sys, json
from urllib.parse import urlparse
hosts = set()
auth = ["accounts.google.com","accounts.youtube.com","login.microsoftonline.com",
        "login.live.com","login.microsoft.com","login.yahoo.com","appleid.apple.com",
        "auth.openai.com","sharepoint.com","office.com","office365.com","live.com"]
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split()
    if len(parts) >= 2:
        h = urlparse(parts[1]).hostname
        if h:
            hosts.add(h)
            p = h.split(".")
            if len(p) > 2:
                hosts.add(".".join(p[-2:]))   # registrable domain
hosts.update(auth)
print(json.dumps(sorted(hosts)))
PY
)"

# 3. Extension files.
cat > "$EXTDIR/manifest.json" <<EOF
{
  "manifest_version": 3,
  "name": "Webapps external-link router",
  "version": "1.0",
  "description": "Routes external http(s) links to Firefox; keeps app and auth domains in-app.",
  "key": "$PUBKEY_B64",
  "permissions": ["nativeMessaging"],
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["allowlist.js", "content.js"],
      "run_at": "document_start",
      "all_frames": true
    }
  ],
  "background": { "service_worker": "background.js" }
}
EOF

# allowlist.js is generated (substituted); content.js is static (has $ regexes, keep literal).
printf 'var __WEBAPPS_ALLOW = %s;\n' "$ALLOW_JSON" > "$EXTDIR/allowlist.js"

cat > "$EXTDIR/content.js" <<'JS'
(function () {
  var ALLOW = new Set(typeof __WEBAPPS_ALLOW !== "undefined" ? __WEBAPPS_ALLOW : []);
  function reg(host) {
    var p = host.split(".");
    return p.length <= 2 ? host : p.slice(-2).join(".");
  }
  function internal(href) {
    try {
      var u = new URL(href, location.href);
      if (u.protocol !== "http:" && u.protocol !== "https:") return true; // mailto:/vscode: -> xdg
      var h = u.hostname;
      if (ALLOW.has(h)) return true;
      if (reg(h) === reg(location.hostname)) return true;                 // same site
      return false;
    } catch (e) { return true; }
  }
  document.addEventListener("click", function (e) {
    var t = e.target;
    var a = t && t.closest ? t.closest("a[href]") : null;
    if (!a || !a.href) return;
    if (internal(a.href)) return;
    e.preventDefault();
    e.stopPropagation();
    try { chrome.runtime.sendMessage({ url: a.href }); } catch (err) {}
  }, true);
})();
JS

cat > "$EXTDIR/background.js" <<'JS'
chrome.runtime.onMessage.addListener(function (msg) {
  if (msg && msg.url) {
    try {
      chrome.runtime.sendNativeMessage("org.fathom.ff_open", { url: msg.url }, function () {
        void chrome.runtime.lastError;
      });
    } catch (e) {}
  }
});
JS

# 4. Native messaging host (reads length-prefixed JSON, opens Firefox).
cat > "$HOST_SCRIPT" <<'PY'
#!/usr/bin/env python3
import sys, struct, json, subprocess

def read_message():
    raw = sys.stdin.buffer.read(4)
    if len(raw) != 4:
        return None
    length = struct.unpack("<I", raw)[0]
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8"))

def send_message(obj):
    data = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()

def main():
    try:
        msg = read_message()
    except Exception:
        return
    url = (msg or {}).get("url", "")
    if isinstance(url, str) and url.startswith(("http://", "https://")):
        subprocess.Popen(["firefox", url], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        send_message({"ok": True})
    else:
        send_message({"ok": False})

if __name__ == "__main__":
    main()
PY
chmod +x "$HOST_SCRIPT"

# 5. Native host manifest in Chromium's host dir(s), locked to this extension id.
for nmd in "${NM_DIRS[@]}"; do
  cat > "$nmd/$HOST_NAME.json" <<EOF
{
  "name": "$HOST_NAME",
  "description": "Open external web-app links in Firefox",
  "path": "$HOST_SCRIPT",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
EOF
done

# 6. Regenerate launchers so they --load-extension the redirector.
"$HOME/.local/bin/build-webapps.sh" >/dev/null

echo "Redirector built."
echo "  extension id : $EXT_ID"
echo "  extension    : $EXTDIR"
echo "  native host  : $HOST_SCRIPT"
echo "  host manifest: ${NM_DIRS[0]}/$HOST_NAME.json"
echo "  allowlisted hosts: $(printf '%s' "$ALLOW_JSON" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')"
