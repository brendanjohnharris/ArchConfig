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
#export GDK_SCALE=1
#export GDK_DPI_SCALE=1.0
#export DISPLAY=:0.0
#alias matlab='export GTK_PATH=/usr/lib/x86_64-linux-gnu/gtk-2.0; export MESA_LOADER_DRIVER_OVERRIDE=i965; /usr/local/MATLAB/R2021a/bin/matlab'
export DISPLAY=:0.0

# Tell julia to use discrete GPU
export DRI_PRIME=1

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Make local binaries available
export PATH="$HOME/.local/bin:$PATH"

# Add TeXLive to path
export PATH="/usr/local/texlive/2024/bin/x86_64-linux:$PATH"

# Some programs, like mpd, need this to manually set
export XDG_CONFIG_HOME="$HOME/.config"

alias startxa='rm $HOME/.xmonad/xmonad.hs; ln -s $HOME/.xmonad/xmonada.hs $HOME/.xmonad/xmonad.hs; xmonad --recompile; startx'
alias startxb='rm $HOME/.xmonad/xmonad.hs; ln -s $HOME/.xmonad/xmonadb.hs $HOME/.xmonad/xmonad.hs; xmonad --recompile; startx'


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/brendan/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/brendan/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/brendan/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/brendan/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

