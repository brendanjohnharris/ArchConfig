#!/bin/sh

userresources=$HOME/.Xresources
usermodmap=$HOME/.Xmodmap
sysresources=/etc/X11/xinit/.Xresources
sysmodmap=/etc/X11/xinit/.Xmodmap

# merge in defaults and keymaps

if [ -f $sysresources ]; then

    xrdb -merge $sysresources

fi

if [ -f $sysmodmap ]; then
    xmodmap $sysmodmap
fi

if [ -f "$userresources" ]; then

    xrdb -merge "$userresources"

fi

if [ -f "$usermodmap" ]; then
    xmodmap "$usermodmap"
fi

# start some nice programs

if [ -d /etc/X11/xinit/xinitrc.d ]; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

# ! This can be done here, but easier to do it with libinput
# xinput set-prop "MSFT0001:01 06CB:CE44 Touchpad" "libinput Natural Scrolling Enabled" 1 # Set the trackpad device, "MSFT0001:01 06CB:CE44 Touchpad", to natural scrolling

# ? envycontrol
# xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --auto

# ? xdg-desktop-portal fux
source /etc/X11/xinit/xinitrc.d/50-systemd-user.sh
systemctl --user start graphical-session.target

# ? Type accents
setxkbmap -option compose:ralt

# Keyboard repeat: 350ms delay before repeat, 50 repeats/sec
xset r rate 350 50

# Compositor: tear-free vsync + damage-tracked compositing (config: ~/.config/picom/picom.conf)
command -v picom >/dev/null && picom -b

# Capture xmonad's stderr so resume-time exceptions/hook errors are recorded
# (was previously discarded to the tty). See ~/.xmonad/xmonad.log.
echo "=== xmonad session start $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$HOME/.xmonad/xmonad.log"
xmonad >> "$HOME/.xmonad/xmonad.log" 2>&1
systemctl --user stop graphical-session.target
