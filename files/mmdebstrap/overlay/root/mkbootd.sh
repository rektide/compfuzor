#!/bin/sh
set -e

[ -z "$EFI" ] && EFI=${1:-/boot/efi}

mkdir -p $EFI/loader/entries

# again hat tip to https://p5r.uk/blog/2020/using-systemd-boot-on-debian-bullseye.html
cat > $EFI/loader/loader.conf <<- EOF
default debian
timeout 2
editor 1
EOF

# i have no idea who generates this line but as i've seen it, it means regenerating the machine-id doesn't affect bootctl
# just comment it out & kernel-install works
sed -i "s/^KERNEL_INSTALL_MACHINE_ID=.*/#&/" /etc/machine-info

[ "$DO" = 1 ] &&  bootctl install --make-machine-id=yes
# check with efibootmgr

mkdir -p $EFI/$(cat /etc/machine-id)
