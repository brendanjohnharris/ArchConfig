#!/usr/bin/env bash
# Generate isolated Chromium "site-specific browser" (SSB) launchers from
# ~/.config/webapps/apps.tsv. Each app runs as:
#
#   chromium --app=<url> --user-data-dir=~/.local/share/webapps-chromium --class=<wm_class>
#
# Why this beats the old `chromium --app` (and pake):
#   * --user-data-dir is a SEPARATE profile -> fully isolated from your main
#     Chromium (own cookies/settings), which was the original complaint. (--profile-directory
#     would have SHARED the main data dir; --user-data-dir does not.)
#   * Blink engine -> fast, working downloads, real editors (Overleaf), unlike WebKitGTK/pake.
#   * mailto:/vscode:/zoommtg: links delegate to native apps via the system xdg handlers.
#   * The web apps share ONE profile, so e.g. your Google login is shared across Gmail/Docs/Drive.
#
# External http(s) links -> default browser (Firefox): handled by the redirector
# extension at ~/.local/share/webapps-chromium-ext, loaded here if present
# (build it with build-webapps-redirector.sh). Without it, external links open in
# an isolated Chromium window.
#
# Usage:  build-webapps.sh           # (re)generate every launcher in the manifest
set -uo pipefail

MANIFEST="$HOME/.config/webapps/apps.tsv"
PROFILE="$HOME/.local/share/webapps-chromium"
EXTDIR="$HOME/.local/share/webapps-chromium-ext"
APPDIR="$HOME/.local/share/applications"
ICONDIR="$HOME/.local/share/icons"
BROWSER="$(command -v chromium || command -v chromium-browser || echo chromium)"

mkdir -p "$PROFILE" "$APPDIR" "$ICONDIR"

# Load the external-link->Firefox redirector extension if it has been built.
loadext=""
[ -d "$EXTDIR" ] && loadext=" --load-extension=$EXTDIR"

gen=0
while IFS=$' \t' read -r name url wm_class flags; do
  case "$name" in ''|\#*) continue ;; esac
  # Basename = wm_class (lowercase) so `gtk-launch <name>` keeps working
  # (e.g. xmobar's date click runs `gtk-launch outlook`).
  base="$wm_class"

  # Per-app icon = the site's favicon (cached); generic web icon if offline/unavailable.
  icon="$ICONDIR/webapp-$wm_class.png"
  if [ ! -s "$icon" ]; then
    host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://([^/]+).*#\1#')"
    curl -fsSL --max-time 8 "https://www.google.com/s2/favicons?domain=$host&sz=128" -o "$icon" 2>/dev/null || true
    [ -s "$icon" ] || rm -f "$icon"
  fi
  [ -s "$icon" ] && icon_line="Icon=$icon" || icon_line="Icon=applications-internet"

  cat > "$APPDIR/$base.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$url  (isolated Chromium web app)
Exec=$BROWSER --app="$url" --user-data-dir=$PROFILE --class=$wm_class$loadext
$icon_line
Terminal=false
Categories=Network;
StartupWMClass=$wm_class
EOF
  gen=$((gen + 1))
done < "$MANIFEST"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPDIR" >/dev/null 2>&1

echo "Generated $gen Chromium SSB launchers in $APPDIR"
echo "  profile (isolated from main Chromium): $PROFILE"
[ -n "$loadext" ] && echo "  external-link->Firefox redirector: loaded" || \
  echo "  external-link->Firefox redirector: NOT built (run build-webapps-redirector.sh)"
