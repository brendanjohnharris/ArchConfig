starship init fish | source

function config
    git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" $argv
end

set fish_greeting ""

# Color scheme
set fish_color_command 6EA0F9
set fish_color_normal normal
set fish_color_quote 88BD69
set fish_color_redirection 4D9393
set fish_color_end FFA829
set fish_color_error F93D53
set fish_color_param B97AD7
set fish_color_comment 777777
set fish_color_match normal
set fish_color_selection F5F5F5
set fish_color_search_match FFCE79
set fish_color_history_current normal
set fish_color_operator 4D9393
set fish_color_escape 4D9393
set fish_color_cwd 88BD69
set fish_color_cwd_root 5081D9
set fish_color_valid_path normal
set fish_color_autosuggestion 5E6167
set fish_color_user 88BD69
set fish_color_host normal
set fish_color_cancel normal
set fish_pager_color_completion normal
set fish_pager_color_description FFCE79 yellow
set fish_pager_color_prefix normal --bold --underline
set fish_pager_color_progress brwhite --background=cyan

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
