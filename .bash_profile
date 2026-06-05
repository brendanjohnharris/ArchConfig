#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

export EDITOR=vim; 

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
#    exec "xmonad --recompile"
    exec startx
fi



# Added by Antigravity CLI installer
export PATH="/home/brendan/.local/bin:$PATH"
