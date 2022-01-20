#  * ███████ ██    ██ ███████ ████████ ███████ ███    ███
#  * ██       ██  ██  ██         ██    ██      ████  ████
#  * ███████   ████   ███████    ██    █████   ██ ████ ██
#  *      ██    ██         ██    ██    ██      ██  ██  ██
#  * ███████    ██    ███████    ██    ███████ ██      ██

# ? These steps should be done manually, since they will vary substantially by system

## * Check available keyboard layouts
#ls /usr/share/kbd/keymaps/**/*.map.gz

## * Load a keyboard layout
#loadkeys <de-latin1>

## * Verify the boot mode (EFI or BIOS; EFI if this file directory exists)
#ls /sys/firmware/efi/efivars

## * Check the internet is on
# ip link
# ping archlinux.org

## * Update the clock
#timedatectl set-ntp true

## * Partition the disks; should always do this manually
## ? At minimum, we need a root (and sometimes an efi) partition. Also good to have a swap.
## fdisk -l

## * Open fdisk
## fdisk /dev/sda
## ? In fdisk, create a new partition table (if neccessary). Then:
## ? Then create partitions for EFI, swap and root (in that order) using fdisk: n (end exit with fdisk: w)

## * Now format the partitions with:
## mkfs.fat -F 32 /dev/sda1 # EFI
## mkswap /dev/sda2 # swap
## mkfs.ext4 /dev/sda3 # root
### etc...

## * Mount the root volume...
## mount /dev/sda3 /mnt

## * ... the EFI volume...
## mount /dev/sda1 /mnt/boot

## * ...and turn on the swap
## swapon /dev/sda2

#  * ██ ███    ██ ███████ ████████  █████  ██      ██
#  * ██ ████   ██ ██         ██    ██   ██ ██      ██
#  * ██ ██ ██  ██ ███████    ██    ███████ ██      ██
#  * ██ ██  ██ ██      ██    ██    ██   ██ ██      ██
#  * ██ ██   ████ ███████    ██    ██   ██ ███████ ███████

# ? These commands can run automatically, but probably best to do them manually

# * Install fundamental packages
pacstrap /mnt base linux linux-firmware vim git

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
sed -i 's/LANG=.*/LANG=en_AU.UTF-8/g' /etc/locale.conf

## ? May need to make the keyboard layout persistent by editing /etc/vconsole.conf to have e.g. KEYMAP=de-latin1


## ? These last steps should also be done manually
## * Set a password and create a user account
# passwd

## * Install a bootloader: grub
## ? BIOS
# arch-chroot /mnt /bin/bash
# pacman -S grub
# grub-install --target=i386-pc /dev/sda
## ? EFI: careful here
# arch-chroot /mnt /bin/bash
# pacman -S grub efibootmgr
# mkdir /boot/efi
# mount /dev/sda1 /boot/efi
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# * Make grub config
# grub-mkconfig -o /boot/grub/grub.cfg

# * And check for other operating systems
# pacman -Sy os-prober
# sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/g' /etc/default/grub
# grub-mkconfig -o /boot/grub/grub.cfg

# * The enable microcode updates, and afterword repeat the grub config
# ? AMD
# pacman -Sy amd-ucode
# ? Intel
# pacman -Sy intel-ucode

# grub-mkconfig -o /boot/grub/grub.cfg

# * Finally, reboot!
# exit
# reboot




