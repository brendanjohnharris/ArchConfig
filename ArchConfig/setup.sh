## ! Make sure you have an internet connection. To do this:
# ip link # ? Identify the network interface, probably the second one on the list
# systemctl enable NetworkManager
# systemctl start NetworkManager
# ? For wifi
# nmcli d wifi list
# nmcli -a d wifi connect <WifiInterface>
# ? For wired
# ip link set <interface> up # ? Set it to UP, by default it is DOWN
# * Also refer to the wifi setup from install.sh

## ! Then clone this repository (after setting up git) with:
# git config --global credential.helper store
# git config --global user.email  "brendanjohnharris@gmail.com"
# git config --global user.name "brendanjohnharris"
# git clone --bare https://github.com/brendanjohnharris/ArchConfig.git $HOME/ArchConfig
# git --git-dir=$HOME/ArchConfig/ --work-tree=$HOME checkout

# * Now we assume the bare git repo for our config is in place. We also assume the current shell is bash. 
# ? `config` now takes the place of `git` for config stuff. Should use config add -u ... to ignore new files
echo 'source $HOME/.bashrc' | sudo tee -a /etc/profile
source $HOME/.bashrc
git --git-dir=$HOME/ArchConfig/ config --local status.showUntrackedFiles no

# * You can change the timeout of sudo by adding 'Defaults timestamp_timeout=<mins>' to:
# sudo EDITOR=vim visudo

# * Grub theme
chmod u+x $HOME/.config/grub2themes/install.sh
$HOME/.config/grub2themes/install.sh -t tela -s 2k

# * Display drivers
sudo pacman -Sy nvidia xf86-video-intel mesa

# * Terminal emulator
sudo pacman -Sy alacritty

# * Window manager
sudo pacman -Sy xorg-xinit xorg-server xorg-xinput xmonad xterm xmonad-contrib xmobar dmenu picom xdotool trayer
# cp /etc/X11/xinit/xinitrc $HOME/.xinitrc
# sed -i '$d' $HOME/.xinitrc
# echo "exec xmonad" >> $HOME/.xinitrc
xmonad --recompile

# * File manager
sudo pacman -Sy nautilus

# * Misc. programs
sudo pacman -Sy firefox quodlibet gimp kdenlive audacity inkscape okular libreoffice-fresh conky yad thunderbird qalculate-gtk

# * Fonts
sudo pacman -Sy base-devel
git clone https://aur.archlinux.org/ttf-juliamono.git $HOME/Downloads/ttf-juliamono/
(cd $HOME/Downloads/ttf-juliamono && makepkg -si)
git clone https://aur.archlinux.org/ttf-mononoki.git $HOME/Downloads/ttf-mononoki/
(cd $HOME/Downloads/ttf-mononoki && makepkg -si)

# * Set the dpi
.....
## TODO: Fix fractional scaling
## TODO: Fix awesome icons not appearing in xmobar, see xmobarrc
## TODO: Add alacritty config
## TODO: Add nitrogen for wallpapers
## TODO: Configure fish shell
## TODO: Add a login manager
## TODO: Setup dmenu shortcuts
## TODO: Configure conky panel, add custom keybindings
## TODO: Configure trackpad gestures and tap to click
## TODO: Fix the 'updating' in status xmobar
## TODO: Fix the backlight and power saving modes with https://git.karaolidis.com/Nikas36/legion-7
## TODO: Fix audio issues: https://blog.karaolidis.com/lenovo-legion-7/
## TODO: Get bluetooth manager gui app
## TODO: Remove some window layouts, too many at the moment


#  * ███    ██  ██████  ████████ ███████ ███████
#  * ████   ██ ██    ██    ██    ██      ██
#  * ██ ██  ██ ██    ██    ██    █████   ███████
#  * ██  ██ ██ ██    ██    ██    ██           ██
#  * ██   ████  ██████     ██    ███████ ███████

# ? You can change the permissions on the .local/bin/ (i.e. important scripts) to executable with:
# git update-index --chmod=+x .local/bin/* 
# ? Edit the dpi settings in ~/.Xresources to change the apparent size of programs and fonts. 


