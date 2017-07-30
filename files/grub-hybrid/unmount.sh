#!/bin/bash

set -e
[ -z "$1" ] && echo "Specify a disk" && exit 1 
DEV=$1
[ ! -b "$DEV" ] && echo "dev '$DEV' not a device" >&2 && exit 1
[ -n "$ENV_BYPASS" ] || source $(command -v envdefault || true) {{DIR}}/env.export >/dev/null

# do unmount

doUnmount(){
	dest=$(eval echo \$PARTITION_$(echo $1|tr /a-z/ /A-Z/))
	# find any mounts with this destination and sort by their path length
	# thus subdirs unmounted first
	mounts=$(mount|grep $dest|awk '{ print length($3) " " $3; }'|sort -r -n|cut -d ' ' -f 2-)

	# unmount each
	for m in $mounts
	do
		echo unmounting $(mount|grep $m|awk '{print $1}') from $m
		umount $m
	done

	# warn if not found
	if [ -z "$mounts" ]
	then
		# not mounted at all - uh ok
		echo "$dest was not mounted"
	fi
}

doUnmount efi
doUnmount linux
