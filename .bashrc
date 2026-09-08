# * Conveniently manipulate the bare repo in ArchConfig with an alias
config() {
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" "$@"
}

# * Secrets (not published)
[ -f ~/.secrets ] && source ~/.secrets

# * Permissions for OS scripts
chmod u+x $HOME/.xmonad/xmonad_keys.sh

# * Set qt theme
export QT_QPA_PLATFORMTHEME=qt6ct # Then select kvantum
export QT_QPA_PLATFORM=xcb
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11

# # Stop matlab from shouting
# export MATLAB_LOG_DIR="$HOME/.matlab/logs"
# export LD_PRELOAD=/usr/lib/libstdc++.so
# export LD_LIBRARY_PATH=/usr/lib/xorg/modules/dri/

# The default browser for xdg-open doesn't seem to be applied everywhere, and keeps getting overwritten, so:
xdg-mime default sioyek.desktop application/pdf
xdg-mime default firefox.desktop x-scheme-handler/https
xdg-mime default firefox.desktop x-scheme-handler/http
export BROWSER=firefox
export READER=sioyek

# * Jabref scaling
export JABREF_OPTIONS="-Dglass.gtk.uiScale=144dpi -Djdk.gtk.version=2"
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1
export DISPLAY=:0.0

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Make local binaries available
export PATH="$HOME/.local/bin:$PATH"

# * Add claude toggle to path
export PATH="$HOME/claude-toggle:$PATH"

# Add TeXLive to path
export PATH="/usr/local/texlive/2024/bin/x86_64-linux:$PATH"

# Add ruby to path
export PATH="$HOME/.local/share/gem/ruby/3.3.0/bin:$PATH"

# Some programs, like mpd, need this to manually set
export XDG_CONFIG_HOME="$HOME/.config"

alias mamba='/home/brendan/miniforge3/bin/mamba'

# >>> juliaup initialize >>>

# !! Contents within this block are managed by juliaup !!

case ":$PATH:" in
    *:/home/brendan/.juliaup/bin:*)
        ;;

    *)
        export PATH=/home/brendan/.juliaup/bin${PATH:+:${PATH}}
        ;;
esac

# <<< juliaup initialize <<<

# * Modern CLI tools (bat/eza/fd/zoxide)
# zoxide: smart dir jumping via `z`/`zi` (cd left untouched in bash; fish uses --cmd cd)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
# eza/bat exposed under distinct names; ls/cat stay as the real coreutils binaries
if command -v eza >/dev/null 2>&1; then
    alias ll='eza -l --git --group-directories-first'
    alias la='eza -la --git --group-directories-first'
    alias lt='eza --tree --level=2'
    alias l='eza'
fi
command -v bat >/dev/null 2>&1 && alias batp='bat'

# * More modern CLI tools (atuin/yazi/zellij/lazygit/dua), guarded on presence
# atuin: shell history (Ctrl-R / Up). Init only when readline line-editing is on
# (emacs/vi mode) -- otherwise atuin's `bind` keybindings warn "line editing not
# enabled". That fires in interactive-but-no-readline shells (IDE shell integration,
# `bash -i` without a tty), where $- still contains 'i', so testing interactivity
# alone is not enough; the line-editing test is the exact condition `bind` needs.
if { shopt -oq emacs || shopt -oq vi; } && command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init bash --disable-up-arrow)"  # Up = native shell history; Ctrl-R = atuin
fi
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
command -v zellij  >/dev/null 2>&1 && alias zj='zellij'
command -v dua     >/dev/null 2>&1 && alias dui='dua interactive'
# yazi: `y` opens the file manager and cd's to wherever you quit.
if command -v yazi >/dev/null 2>&1; then
    y() {
        local tmp; tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        local cwd; cwd="$(command cat -- "$tmp")"
        [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
        rm -f -- "$tmp"
    }
fi
