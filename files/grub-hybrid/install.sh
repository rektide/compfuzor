#!/bin/bash

# Generally follows multistrap's disk-gpt.sh. 

set -e
[ -z "$1" ] && echo "Specify a disk" && exit 1 
DEV=$1
[ ! -b "$DEV" ] && echo "dev '$DEV' not a device" >&2 && exit 1
[ -n "$ENV_BYPASS" ] || source $(command -v envdefault || true) /opt/grub-hybrid-main/env.export >/dev/null

# efi  partition

grub-install \
	--target=x86_64-efi \
	--efi-directory=$DIR_EFI \
	--boot-directory=$DIR_BOOT \
	--removable \
	--recheck

# bios boot partition

grub-install \
	--target=i386-pc \
	--boot-directory=$DIR_BOOT \
	--recheck \
	$DEV

# linux partition

grub-install \
	--target=i386-pc \
	--boot-directory=$DIR_BOOT \
	--recheck \
	--force \ # blocklists
	"$PARTITION_LINUX"
