#  * ███████ ██    ██ ███████ ████████ ███████ ███    ███
#  * ██       ██  ██  ██         ██    ██      ████  ████
#  * ███████   ████   ███████    ██    █████   ██ ████ ██
#  *      ██    ██         ██    ██    ██      ██  ██  ██
#  * ███████    ██    ███████    ██    ███████ ██      ██

# ? These steps should all be done manually, since they will vary by system

# * Check available keyboard layouts
ls /usr/share/kbd/keymaps/**/*.map.gz

# * Load a keyboard layout
loadkeys de-latin1

# * Verify the boot mode (EFI or BIOS; EFI if this file directory exists)
ls /sys/firmware/efi/efivars

# * Check the internet is on
ip link
ping archlinux.org

# * Update the clock
timedatectl set-ntp true

# * Partition the disks; should always do this manually
# ? At minimum, we need a root (and sometimes an efi) partition. Also good to have a swap.
fdisk -l

# * Open fdisk
fdisk /dev/sda
# ? In fdisk, create a new partition table (if neccessary; don't do this if dual booting). Then:
# ? Then create partitions for EFI, swap and root (in that order) using fdisk: n (end exit with fdisk: w)

# * Now format the partitions with:
mkfs.fat -F 32 /dev/sda1 # EFI
mkswap /dev/sda2 # swap
mkfs.ext4 /dev/sda3 # root
# etc...

# * Mount the root volume...
mount /dev/sda3 /mnt

# * ... the EFI volume...
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot

# * ...and turn on the swap
swapon /dev/sda2

#  * ██ ███    ██ ███████ ████████  █████  ██      ██
#  * ██ ████   ██ ██         ██    ██   ██ ██      ██
#  * ██ ██ ██  ██ ███████    ██    ███████ ██      ██
#  * ██ ██  ██ ██      ██    ██    ██   ██ ██      ██
#  * ██ ██   ████ ███████    ██    ██   ██ ███████ ███████

# * Install fundamental packages
pacstrap /mnt base linux linux-firmware vim git sudo wpa_supplicant networkmanager

# * Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# * Change the root directory
arch-chroot /mnt

# * Set the time zone.
ln -sf /usr/share/zoneinfo/Australia/Sydney /etc/localtime
hwclock --systohc

# * Choose a locale by uncommenting /etc/locale.gen, then generate the locales and set a language
sed -i 's/#en_AU.UTF-8 UTF-8/en_AU.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen
echo 'LANG=en_AU.UTF-8/g' > /etc/locale.conf
# ? Maybe do this last in vim? If doing this without root, can write in vim with command `:w !sudo tee %` (pipes through tee with su privelages)

# ? May need to make the keyboard layout persistent by editing /etc/vconsole.conf to have e.g. KEYMAP=de-latin1


# ? These last steps should also be done manually
# * Set a password and create a user account
passwd

# * Make a user or two
useradd -m brendan
passwd brendan
usermod -aG wheel,audio,video,optical,storage brendan
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers

# * Chroot for bootloader setup
exit
arch-chroot /mnt /bin/bash

# * Install a bootloader: grub
# ? BIOS
pacman -S grub
grub-install --target=i386-pc /dev/sda
# ? EFI: careful here. /boot/efi should already be made
pacman -S grub efibootmgr
mount /dev/sda1 /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# * Make grub config
grub-mkconfig -o /boot/grub/grub.cfg

# * And check for other operating systems
pacman -Sy os-prober
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/g' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# * The enable microcode updates, and afterword repeat the grub config
# ? AMD
pacman -Sy amd-ucode
# ? Intel
pacman -Sy intel-ucode

grub-mkconfig -o /boot/grub/grub.cfg

# * Should now:
# - Install graphics card drivers

# * Finally, reboot, remove the install medium and create a new user on the system
exit
umount -R /mnt
shutdown now


# ! If, for some reason, you need to return to the iso environment (e.g. wifi tools were not installed correctly, and you have no wifi as a user) then boot from the iso and:
ip link
mount /dev/sda3 /mnt
arch-chroot /mnt /bin/bash
# ! Now you can pacman as you like