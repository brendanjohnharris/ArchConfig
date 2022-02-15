# * Conveniently manipulate the bare repo is .dotfiles with an alias
config () {
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" "$@"
}