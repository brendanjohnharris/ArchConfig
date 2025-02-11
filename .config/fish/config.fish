starship init fish | source

function config; git --git-dir="$HOME/ArchConfig" --work-tree="$HOME" $argv; end
function qload; ssh headnode.physics.usyd.edu.au -t "qload"; end
function monitor; ssh headnode.physics.usyd.edu.au -t "monitor"; end

set fish_greeting ""

# Color scheme
set fish_color_command 51afef
set fish_color_normal normal
set fish_color_quote 98be65
set fish_color_redirection 46d9ff
set fish_color_end da8548
set fish_color_error ff6c6b
set fish_color_param c678dd
set fish_color_comment 6d757d
set fish_color_match normal
set fish_color_selection dfdfdf
set fish_color_search_match ecbe7b
set fish_color_history_current normal
set fish_color_operator 4db5bd
set fish_color_escape 4db5bd
set fish_color_cwd 98be65
set fish_color_cwd_root 3071db
set fish_color_valid_path normal
set fish_color_autosuggestion 5699af
set fish_color_user 98be65
set fish_color_host normal
set fish_color_cancel normal
set fish_pager_color_completion normal
set fish_pager_color_description ecbe7b yellow
set fish_pager_color_prefix normal --bold --underline
set fish_pager_color_progress brwhite --background=cyan

set -Ux CRYPTOGRAPHY_OPENSSL_NO_LEGACY 1



# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /home/brendan/miniconda3/bin/conda
    eval /home/brendan/miniconda3/bin/conda "shell.fish" "hook" $argv | source
else
    if test -f "/home/brendan/miniconda3/etc/fish/conf.d/conda.fish"
        . "/home/brendan/miniconda3/etc/fish/conf.d/conda.fish"
    else
        set -x PATH "/home/brendan/miniconda3/bin" $PATH
    end
end
# <<< conda initialize <<<

