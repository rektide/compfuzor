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

[ "$DO" = 1 ] &&  bootctl install --path=$EFI
# check with efibootmgr

mkdir -p $EFI/$(cat /etc/machine-id)
