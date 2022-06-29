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
export LD_PRELOAD=/usr/lib/libstdc++.so
export LD_LIBRARY_PATH=/usr/lib/xorg/modules/dri/

# The default browser for xdg-open doesn't seem to be applied everywhere, and keeps getting overwritten, so:
xdg-mime default okularApplication_pdf.desktop application/pdf
xdg-mime default firefox.desktop x-scheme-handler/https
xdg-mime default firefox.desktop x-scheme-handler/http
export BROWSER=firefox
export READER=okular

#export GDK_SCALE=1
#export GDK_DPI_SCALE=1.0
#export DISPLAY=:0.0
#alias matlab='export GTK_PATH=/usr/lib/x86_64-linux-gnu/gtk-2.0; export MESA_LOADER_DRIVER_OVERRIDE=i965; /usr/local/MATLAB/R2021a/bin/matlab'
export DISPLAY=:0.0

# Tell julia to use discrete GPU
export DRI_PRIME=1

