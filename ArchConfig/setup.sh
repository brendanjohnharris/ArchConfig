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
sudo pacman -Syu nvidia xf86-video-intel mesa

# * Terminal emulator
sudo pacman -Syu alacritty

# * Time synchronisation via network
sudo timedatectl set-ntp true

# * Window manager
sudo pacman -Syu xorg-xinit xorg-server xorg-xinput xmonad xterm xmonad-contrib xmobar dmenu picom xdotool trayer
# cp /etc/X11/xinit/xinitrc $HOME/.xinitrc
# sed -i '$d' $HOME/.xinitrc
# echo "exec xmonad" >> $HOME/.xinitrc
xmonad --recompile

# * File manager
sudo pacman -Syu nautilus

# * Misc. programs
sudo pacman -Syu firefox quodlibet gimp kdenlive audacity inkscape okular libreoffice-fresh conky yad qalculate-gtk network-manager-applet caprine ffmpeg gnome-keyring seahorse asp pacman-contrib

# * AUR helper
sudo pacman -Syu base-devel
git clone https://aur.archlinux.org/paru.git $HOME/Downloads/paru/
(cd $HOME/Downloads/paru && makepkg -si)

# * Fontsctrl
paru -Sy ttf-juliamonothunderbird
paru -Sy ttf-mononoki

# * Email client
paru -Sy betterbird

# * Enable bluetooth device auto-detect by editing sudo vim /etc/bluetooth/main.conf and setting AutoEnable=true
sudo pacman -Syu bluez bluez-utils blueman pulseaudio pulseaudio-alsa pulseaudio-bluetooth pavucontrol
sudo systemctl enable bluetooth

# * Brightness control
sudo pacman -Sy acpilight

## TODO: Set bluetooth to autostart
## TODO: Increase the width of the xmobar
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
## TODO: Set the GTK and QT themes to match onedark pro
## TODO: Enable and set trackpad gestures
## TODO: Setup HDR display
## TODO: Setup notifications via dunst
## TODO: Set alt-tab to cycle through windows in both floating and tiled mode
## TODO: Make a browser scratchpad
## TODO: Add gpu to conky and xmobar
## TODO: Bind function keys to brightness


#  * ███    ██  ██████  ████████ ███████ ███████
#  * ████   ██ ██    ██    ██    ██      ██
#  * ██ ██  ██ ██    ██    ██    █████   ███████
#  * ██  ██ ██ ██    ██    ██    ██           ██
#  * ██   ████  ██████     ██    ███████ ███████

# ? You can change the permissions on the .local/bin/ (i.e. important scripts) to executable with:
# git update-index --chmod=+x .local/bin/* 
# ? Edit the dpi settings in ~/.Xresources to change the apparent size of programs and fonts. 
# ? Enable services at login with systemctl --user enable <service>, which will add that service to ....
# ? Gnome keyring lets apps like vscode automatically login to accounts. If you want gnome keyring to automatically unlock the default account, rather than always prompting for a password, simply set the keyring password to the login password


# ! Also need to patch the kernel to fix audio issues on the legion 7i. The relevant diff is here:
# ? https://lkml.org/lkml/diff/2022/1/21/656/1
# ? And some simple instructions to apply the patch are here:
# ? https://www.youtube.com/watch?v=fPyEolslSTM&ab_channel=pantheist46n2
# ! ACTUALLY you need to build a linux kernel with a new version that 5.17-rc2. How to do that here: https://www.youtube.com/watch?v=APQY0wUbBow&ab_channel=DenshiVideo

# ! Can get rid of grey overlay when sharing zoom screen with: https://bugs.archlinux.org/task/66469. Copy picom conf to ~/.congig/picom/picom.conf

