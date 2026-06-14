#!/usr/bin/env bash
# One-shot installer for the "round 2" CLI tools + sioyek.
# Run with: bash ~/install-newtools.sh   (it will prompt for sudo)
# Idempotent: every install uses --needed, so re-running is safe.
# Mirrors the lines added to ~/ArchConfig/setup.sh.
set -euo pipefail

echo "==> Installing CLI tools from the official repos..."
# atuin   : shell history (Ctrl-R / Up)         lazygit : terminal git UI
# yazi    : terminal file manager (`y`)         tealdeer: fast `tldr` client
# zellij  : terminal multiplexer (`zj`)         dua-cli : disk usage (`dui`)
# ffmpegthumbnailer/7zip/poppler/jq/ripgrep : yazi preview + search helpers
sudo pacman -Syu --needed atuin yazi zellij lazygit tealdeer dua-cli \
    ffmpegthumbnailer 7zip poppler jq ripgrep

echo "==> Priming the tealdeer page cache..."
tldr --update || true

echo "==> Installing sioyek (AUR via paru) + official-binary shadow..."
# sioyek becomes the default PDF reader; okular stays installed as an annotation fallback.
# The AUR build hard-aborts on search (Arch -D_GLIBCXX_ASSERTIONS + upstream #1401), so we
# keep it for its .desktop/icon/assets and shadow its binary with the official build.
# paru -S --needed sioyek
# ~/.local/bin/sioyek-official-update

echo "==> Installing pake-cli (for the chromium-app -> pake web-app migration)..."
# Builds Tauri/WebKitGTK web apps. The actual migration is a separate, deliberate
# step: run ~/.local/bin/build-webapps.sh after this (it's slow — Rust compiles).
sudo npm install -g pake-cli

cat <<'EOF'

==> Done. Next steps:
  * Web apps (optional, slow): build the pake apps with
        ~/.local/bin/build-webapps.sh         # all, or pass a name e.g. outlook
    then verify and, if needed, restore with  build-webapps.sh --restore
  * Recompile xmonad (M-C-r) so the reader scratchpad (M-s r) and the app grid
    point at sioyek, and so every fathom *.template re-renders.
  * Verify sioyek's WM_CLASS matches the scratchpad rule:
        sioyek & sleep 1; xprop WM_CLASS   # click the sioyek window; expect "sioyek"
    If it differs, update findReader in ~/.xmonad/xmonad.hs.
  * Open a fresh shell to pick up atuin (Ctrl-R), `y` (yazi), and lg/zj/dui aliases.
  * Optional, for sioyek highlight-embedding (`_embed_annotations`):
        paru -S python-sioyek
EOF
