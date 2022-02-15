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
# git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME checkout

# * Now we assume the bare git repo for our config is in place. We also assume the current shell is bash. 
# ? `config` now takes the place of `git` for config stuff. Should use config add -u ... to ignore new files
echo 'source $HOME/.bashrc' >> /etc/profile
source $HOME/.bashrc
git --git-dir=$HOME/.dotfiles/ config --local status.showUntrackedFiles no
cd $HOME

# * Grub theme
chmod u+x $HOME/.config/grub2themes/install.sh
$HOME/.config/grub2themes/install.sh -t tela -s 2k

# * Display drivers
pacman -Sy nvidia xf86-video-intel mesa

# * Terminal emulator
pacman -Sy alacritty

# * Window manager
pacman -Sy xorg-xinit xorg-server xorg-xinput xmonad xterm xmonad-contrib xmobar dmenu picom xdotool
cp /etc/X11/xinit/xinitrc $HOME/.xinitrc
sed -i '$d' $HOME/.xinitrc
echo "exec xmonad" >> $HOME/.xinitrc
xmonad --recompile

# * File manager
pacman -Sy nautilus

# * Misc. programs
pacman -Sy firefox quodlibet gimp kdenlive audacity inkscape okular libreoffice-fresh conky yad thunderbird qalculate-gtk

# * Change the scrolling direction
xinput set-prop 14 350 1

# * Set the dpi
.....
## TODO: Fix fractional scaling
## TODO: Remove all applications from root, and move all config files to user. Root should only have vim.


