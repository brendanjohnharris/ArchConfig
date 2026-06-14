#!/usr/bin/env bash
# Build standalone web apps with pake (Tauri/WebKitGTK) from ~/.config/webapps/apps.tsv,
# replacing the old `chromium --app` .desktop launchers.
#
# Why extract the binary from the .deb instead of using the AppImage: this machine
# has fuse3 but not fuse2, so classic AppImages won't self-mount. The .deb's ELF
# binary runs directly with no fuse dependency.
#
# Reversible: the original chromium .desktop files are MOVED to
# ~/.config/webapps/chromium-backup/ (not deleted), and `gtk-launch <name>` keeps
# working because the new .desktop reuses the same basename.
#
# Usage:
#   build-webapps.sh            # build every app in the manifest
#   build-webapps.sh outlook    # build only the named app(s)
#   build-webapps.sh --restore  # restore the chromium .desktop files from backup
#
# Prereqs (already present on this box): node+npm, cargo+rustc, webkit2gtk-4.1,
# libappindicator, binutils (ar), tar. Install pake once with:  npm install -g pake-cli
set -uo pipefail

MANIFEST="${HOME}/.config/webapps/apps.tsv"
INJECT_CSS="${HOME}/.config/webapps/fathom-webapp.css"
BIN_DIR="${HOME}/.local/bin/webapps"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons"
BACKUP_DIR="${HOME}/.config/webapps/chromium-backup"
BUILD_ROOT="$(mktemp -d -t pake-build.XXXXXX)"
trap 'rm -rf "$BUILD_ROOT"' EXIT

mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR" "$BACKUP_DIR"

# --restore: put the chromium launchers back and bail.
if [ "${1:-}" = "--restore" ]; then
    n=0
    for f in "$BACKUP_DIR"/*.desktop; do
        [ -e "$f" ] || continue
        cp -f "$f" "$APP_DIR/$(basename "$f")"
        n=$((n + 1))
    done
    echo "Restored $n chromium .desktop file(s) from $BACKUP_DIR."
    exit 0
fi

if ! command -v pake >/dev/null 2>&1; then
    echo "ERROR: pake not found. Install it with:  npm install -g pake-cli" >&2
    exit 1
fi

# Optional filter: only build the apps named on the command line.
declare -A WANT=()
for a in "$@"; do WANT["$a"]=1; done

built=() failed=() skipped=()

while IFS=$'\t' read -r name url wm_class flags; do
    # Skip comments / blank lines.
    case "$name" in ''|\#*) continue ;; esac
    if [ "${#WANT[@]}" -gt 0 ] && [ -z "${WANT[$name]:-}" ]; then continue; fi

    if [ "$flags" = "TEST" ]; then
        echo ">> $name is flagged TEST (may not work under WebKitGTK) — building anyway."
        flags="-"
    fi
    extra=()
    [ "$flags" != "-" ] && extra=($flags)

    echo "==> Building $name  ($url)"
    workdir="$BUILD_ROOT/$name"
    mkdir -p "$workdir"
    inject=()
    [ -f "$INJECT_CSS" ] && inject=(--inject "$INJECT_CSS")

    if ! ( cd "$workdir" && pake "$url" --name "$name" --hide-title-bar "${inject[@]}" "${extra[@]}" ); then
        echo "   !! pake build failed for $name" >&2
        failed+=("$name"); continue
    fi

    deb="$(find "$workdir" -maxdepth 2 -name '*.deb' | head -1)"
    if [ -z "$deb" ]; then
        echo "   !! no .deb produced for $name" >&2
        failed+=("$name"); continue
    fi

    # Unpack the .deb (ar -> data.tar.*) and lift out the ELF binary + icon.
    ex="$workdir/extract"; mkdir -p "$ex"
    ( cd "$ex" && ar x "$deb" && tar xf data.tar.* )
    binsrc="$(find "$ex/usr/bin" -maxdepth 1 -type f 2>/dev/null | head -1)"
    if [ -z "$binsrc" ]; then
        echo "   !! no binary inside $deb for $name" >&2
        failed+=("$name"); continue
    fi
    install -Dm755 "$binsrc" "$BIN_DIR/$name"

    # Largest packaged PNG icon, if any (pick by byte size; sort -k0 was invalid).
    iconsrc="$(find "$ex/usr/share/icons" -name '*.png' -printf '%s\t%p\n' 2>/dev/null | sort -n | tail -1 | cut -f2-)"
    icon_line="Icon=$name"
    if [ -n "$iconsrc" ]; then
        install -Dm644 "$iconsrc" "$ICON_DIR/$name.png"
        icon_line="Icon=$ICON_DIR/$name.png"
    fi

    # Back up the old chromium .desktop (once), then install the pake one in its place.
    if [ -f "$APP_DIR/$name.desktop" ] && ! [ -f "$BACKUP_DIR/$name.desktop" ]; then
        if grep -q 'chromium --app' "$APP_DIR/$name.desktop" 2>/dev/null; then
            mv "$APP_DIR/$name.desktop" "$BACKUP_DIR/$name.desktop"
        fi
    fi
    cat > "$APP_DIR/$name.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=Web app ($url) built with pake
Exec=$BIN_DIR/$name %U
$icon_line
Terminal=false
Categories=Network;
StartupWMClass=$wm_class
EOF

    built+=("$name")
done < "$MANIFEST"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" >/dev/null 2>&1

echo
echo "Built:   ${built[*]:-none}"
echo "Failed:  ${failed[*]:-none}"
cat <<EOF

Next:
  * Launch one and confirm its WM_CLASS matches the manifest:
        $BIN_DIR/<name> & sleep 2; xprop WM_CLASS   # click the window
    If it differs, fix the wm_class column in $MANIFEST and re-run for that app.
  * The xmobar date click runs \`gtk-launch outlook\` — it now opens the pake app.
  * Originals are safe in $BACKUP_DIR; undo everything with:  build-webapps.sh --restore
EOF
