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
sudo pacman -Syu xorg-xinit xorg-server xorg-xinput xmonad xterm xmonad-contrib xmobar rofi picom xdotool trayer
# cp /etc/X11/xinit/xinitrc $HOME/.xinitrc
# sed -i '$d' $HOME/.xinitrc
# echo "exec xmonad" >> $HOME/.xinitrc
xmonad --recompile

# * File manager
sudo pacman -Syu nautilus

# * Misc. programs
sudo pacman -Syu firefox mpd cantata mpc gimp kdenlive audacity inkscape okular libreoffice-fresh conky yad qalculate-gtk network-manager-applet ffmpeg gnome-keyring seahorse asp pacman-contrib htop flameshot bc qutebrowser dunst lxappearance arc-gtk-theme kvantum feh vlc lxsession rofi onedrive-abraunegg onedrive_tray-git qt5-base piper gnome-characters peek ranger xclip nvidia-settings

# * Onedrive tray service
sudo cp /usr/lib/systemd/user/onedrive_tray.service $HOME/.config/systemd/user/
systemctl --user enable onedrive_tray.service

# * AUR helper
sudo pacman -Syu base-devel
git clone https://aur.archlinux.org/paru.git $HOME/Downloads/paru/
(cd $HOME/Downloads/paru && makepkg -si)

# * Pretty terminal
paru -Syu fastfetch
sudo rm /usr/share/themes/Arc-Dark/gtk-2.0/gtkrc 
sudo ln -s ~/.config/.gtkcolorscheme /usr/share/themes/Arc-Dark/gtk-2.0/gtkrc 

# * Fonts
sudo pacman -Syu fontconfig
paru -Sy ttf-juliamono ttf-mononoki nerd-fonts-source-code-pro ttf-font-awesome ttf-ms-win10-auto

# * Printing
sudo pacman -Syu cups cups-pdf avahi nss-mdns samba
paru -Syu samsung-unified-driver epson-inkjet-printer-workforce-635-nx625-series gutenprint foomatic-db-gutenprint-ppds
sudo systemctl enable cups.socket
# Then set up avahi local hostnames: https://wiki.archlinux.org/title/Avahi#Hostname_resolution. Also see https://wiki.archlinux.org/title/CUPS#Network

# * Icon theme
sudo pacman -Syu hicolor-icon-theme papirus-icon-theme

# * Email client
paru -Sy betterbird

# * Enable bluetooth device auto-detect by editing sudo vim /etc/bluetooth/main.conf and setting AutoEnable=true
sudo pacman -Syu bluez bluez-utils blueman pulseaudio pulseaudio-alsa pulseaudio-bluetooth pavucontrol volumeicon alsa-utils gstreamer gst-plugins-good gst-libav
sudo systemctl enable bluetooth

# * Brightness control
sudo pacman -Syu acpilight

# * Screengrab gifs
paru -Syu peek

# * Trackpad gestures
sudo pacman -Syu xf86-input-libinput wmctrl
paru -Syu libinput-gestures
libinput-gestures-setup desktop
libinput-gestures-setup autostart
# sudo ln -s $HOME/ArchConfig/30-touchpad.conf /etc/X11/xorg.conf.d/30-touchpad.conf
# sudo ln -s $HOME/ArchConfig/libinput-gestures.service /etc/systemd/system/libinput-gestures.service
# sudo systemctl enable libinput-gestures.service
# ! To actually have this work, edit sudoers to include: ALL ALL = NOPASSWD: /usr/bin/libinput-gestures

# * Low battery warning
systemctl --user enable batterymonitor.service

# * Downgrade packages
paru -Syu downgrade

# * Fish shell
sudo pacman -Syu fish starship fisher


# # * Turn off discrete gpu
# ! See https://github.com/Askannz/optimus-manager
# sudo pacman -Syu bumblebee bbswitch
# echo 'blacklist nvidia' | sudo tee -a /etc/modprobe.d/BLACKLIST-video.conf
# sudo modprobe bbswitch
# sudo gpasswd -a brendan bumblebee

# sudo pacman -Syu acpi_call
# modprobe acpi_call
# tr < /usr/share/acpi_call/examples/turn_off_gpu.sh -d '\000' > $HOME/.local/bin/turn_off_gpu.sh

# * Piper for multi-button mice
sudo pacman -Syu piper

## TODO: Configure fish shell
## TODO: Set the GTK and QT themes to match onedark pro (PLUS OKULAR!)
## TODO: Setup HDR display
## TODO: Find a way to have super+0 bound to a workspace
## TODO: Find a way to execute the action script for the battery icon as root/sudo automatically
## TODO: Change the background colours of the Arc theme to be consistent with One Dark Pro
## TODO: Add dynamic icons (XMonad.Hooks.DynamicIcons) to tab names
## TODO: Install PipeWire for better audio


#  * ███    ██  ██████  ████████ ███████ ███████
#  * ████   ██ ██    ██    ██    ██      ██
#  * ██ ██  ██ ██    ██    ██    █████   ███████
#  * ██  ██ ██ ██    ██    ██    ██           ██
#  * ██   ████  ██████     ██    ███████ ███████

# ? You can change the permissions on the .local/bin/ (i.e. important scripts) to executable with:
# config update-index --chmod=+x .local/bin/* 
# ? Edit the dpi settings in ~/.Xresources to change the apparent size of programs and fonts. 
# ? Enable services at login with systemctl --user enable <service>, which will add that service to ....
# ? Gnome keyring lets apps like vscode automatically login to accounts. If you want gnome keyring to automatically unlock the default account, rather than always prompting for a password, simply set the keyring password to the login password


# ! Also need to patch the kernel to fix audio issues on the legion 7i. The relevant diff is here:
# ? https://lkml.org/lkml/diff/2022/1/21/656/1
# ? And some simple instructions to apply the patch are here:
# ? https://www.youtube.com/watch?v=fPyEolslSTM&ab_channel=pantheist46n2
# ! ACTUALLY you need to build a linux kernel with a new version that 5.17-rc2. How to do that here: https://www.youtube.com/watch?v=APQY0wUbBow&ab_channel=DenshiVideo.
# ! Or a method that actually works: https://wiki.archlinux.org/title/Kernel/Traditional_compilation#Install_the_core_packages
# !! OR just wait for the stable release of 5.17... :(

# ! Can get rid of grey overlay when sharing zoom screen with: https://bugs.archlinux.org/task/66469. Copy picom conf to ~/.congig/picom/picom.conf

# ! To prevent entering a sudo password everytime you want to change the power saving mode, use `sudo -E=vim visudo` to add:
# ALL ALL = (ALL) NOPASSWD: /usr/bin/tee /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
# ! To the sudoers file, just after the `root ALL=(ALL:ALL) ALL` line

# ! A good tool for easily customising the arc GTK theme
# https://github.com/geokapp/arc-variants

# ! If nautilus is opening file pickers in full screen, try:
# dconf write /org/gnome/nautilus/window-state/maximized false

# ! To enabel hibernate, add the kernel parameter: resume=/dev/archVolumeGroup/archLogicalVolume
# ! via GRUB as descirbed here: https://wiki.archlinux.org/title/kernel_parameters#GRUB 
# e.g. GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet resume=/dev/nvme0n1p5"

# ! To automatically authenticate with the gnome keyring at login (and when not using a display manager), follow: https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step

# ! Can build onedrive_tray manually, and replace the blue icon with a better white one

# !  lspci -v | grep -E 'VGA|3D' to detect if descrete gpu is powered on


# ? To temporarily disable sleep timeout:
# https://askubuntu.com/questions/47311/how-do-i-disable-my-system-from-going-to-sleep

# ! See here for installing new matlab toolboxes
# https://au.mathworks.com/matlabcentral/answers/334889-can-t-install-any-toolboxes-because-can-t-write-to-usr-local-matlab-r2017

# ! See here for how to enable USyd printing: https://www.maths.usyd.edu.au/u/psz/smri.html
# To start, run `sudo /etc/papercut/client/pc-client-launcher`.