# * Conveniently manipulate the bare repo in ArchConfig with an alias
config () {
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" "$@"
}

# * Permissions for OS scripts
chmod u+x $HOME/.xmonad/xmonad_keys.sh