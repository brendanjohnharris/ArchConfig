starship init fish | source

function config
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" $argv
end

set fish_greeting ""

# Fish prompt colours are generated from the Fathom palette into
# conf.d/fathom_colors.fish by ~/.xmonad/bin/gen-fathom-colors.sh (auto-sourced).

set -Ux CRYPTOGRAPHY_OPENSSL_NO_LEGACY 1

zoxide init fish --cmd cd | source

# Modern CLI tools: eza/bat under distinct names (ls/cat stay as coreutils)
if type -q eza
    alias ll 'eza -l --git --group-directories-first'
    alias la 'eza -la --git --group-directories-first'
    alias lt 'eza --tree --level=2'
    alias l 'eza'
end
type -q bat; and alias batp 'bat'

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /home/brendan/miniconda3/bin/conda
    eval /home/brendan/miniconda3/bin/conda "shell.fish" hook $argv | source
else
    if test -f "/home/brendan/miniconda3/etc/fish/conf.d/conda.fish"
        . "/home/brendan/miniconda3/etc/fish/conf.d/conda.fish"
    else
        set -x PATH /home/brendan/miniconda3/bin $PATH
    end
end
# <<< conda initialize <<<
