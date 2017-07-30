#!/bin/bash

# Generally follows multistrap's disk-gpt.sh. 

set -e
[ -n "$ENV_BYPASS" ] || source $(command -v envdefault || true) {{DIR}}/env.export >/dev/null

# efi  partition

grub-install \
	--target=x86_64-efi \
	--efi-directory=$dir_efi
	--boot-directory=$dir_boot \
	--removable \
	--recheck

# bios boot partition

grub-install \
	--target=i386-pc \
	--boot-directory=$dir_boot \
	--recheck \
	"${drive}${PARTITION_BIOS}"

# linux partition

grub-install \
	--target=i386-pc \
	--boot-directory=$dir_boot \
	--recheck \
	"${drive}${PARTITION_LINUX}"
