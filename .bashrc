# * Conveniently manipulate the bare repo in ArchConfig with an alias
config () {
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" "$@"
}

# * Permissions for OS scripts
chmod u+x $HOME/.xmonad/xmonad_keys.sh

# * Set qt theme:
QT_STYLE_OVERRIDE="kvantum"

# Stop matlab from shouting
export MATLAB_LOG_DIR="$HOME/.matlab/logs"

# The default browser for xdg-open doesn't seem to be applied everywhere, so:
export BROWSER=firefox

export GDK_SCALE=1
export GDK_DPI_SCALE=1.0

