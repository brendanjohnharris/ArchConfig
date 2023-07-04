# Arch
A personal guide/script for installing and configuring Arch (`./install.sh`) and my config files (`./.*`)

Everything in `install.sh` should be executed manually from the bootable install environment.
Then, everything in `setup.sh` can be executed automatically by this file as a shell script as the root user of the now installed Arch OS (before running, follow the few manual instructions given at the start of `setup.sh`).

# ¡PSA!

If you find yourself in times of trouble, whip out the Arch-iso thumb drive you keep in your pocket and boot into it. Then:
```
mount /dev/nvme0n1p6 /mnt
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt
pacman -Syu linux linux-headers intel-ucode 
mkinitcpio -P
```
If that doesn't help, try deleting `/boot/initramfs-linux.img`, `/boot/intel-ucode.img`, and `/boot/vmlinuz-linux` and then running `mkinitcpio -P` again.

### Links:
- https://wiki.archlinux.org
- https://www.atlassian.com/git/tutorials/dotfiles
- https://dev.to/bowmanjd/store-home-directory-config-files-dotfiles-in-git-using-bash-zsh-or-powershell-the-bare-repo-approach-35l3


