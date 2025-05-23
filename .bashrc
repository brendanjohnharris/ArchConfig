# * Conveniently manipulate the bare repo in ArchConfig with an alias
config() {
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" "$@"
}

# * Permissions for OS scripts
chmod u+x $HOME/.xmonad/xmonad_keys.sh

# * Set qt theme:
QT_STYLE_OVERRIDE="kvantum"

# Stop matlab from shouting
export MATLAB_LOG_DIR="$HOME/.matlab/logs"
export LD_PRELOAD=/usr/lib/libstdc++.so
export LD_LIBRARY_PATH=/usr/lib/xorg/modules/dri/

# The default browser for xdg-open doesn't seem to be applied everywhere, and keeps getting overwritten, so:
xdg-mime default okularApplication_pdf.desktop application/pdf
xdg-mime default firefox.desktop x-scheme-handler/https
xdg-mime default firefox.desktop x-scheme-handler/http
export BROWSER=firefox
export READER=okular

# * Jabref scaling
export JABREF_OPTIONS="-Dglass.gtk.uiScale=144dpi -Djdk.gtk.version=2"
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1
export DISPLAY=:0.0

# Tell julia to use discrete GPU
export DRI_PRIME=1

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Make local binaries available
export PATH="$HOME/.local/bin:$PATH"

# Add TeXLive to path
export PATH="/usr/local/texlive/2024/bin/x86_64-linux:$PATH"

# Add ruby to path
export PATH="$HOME/.local/share/gem/ruby/3.3.0/bin:$PATH"

# Some programs, like mpd, need this to manually set
export XDG_CONFIG_HOME="$HOME/.config"

alias mamba='/home/brendan/miniforge3/bin/mamba'
