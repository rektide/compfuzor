#!/bin/bash

set -e
[ -z "$1" ] && echo "Specify a disk" && exit 1 
DEV=$1
[ ! -b "$DEV" ] && echo "dev '$DEV' not a device" >&2 && exit 1
[ -n "$ENV_BYPASS" ] || source $(command -v envdefault || true) {{DIR}}/env.export >/dev/null

# do mount

doMount(){
	part=$(eval echo \$PARTITION_$(echo $1|tr /a-z/ /A-Z/))
	options=$(eval echo \$PARTITION_$(echo $1|tr /a-z/ /A-Z/)_OPTIONS)
	[ -n "$options" ] && options="-o $options"
	found=$(mount|grep "$part" || true)
	dest=$VAR/$1
	if [ -z "$found" ]
	then
		# not mounted at all - great - mount
		mount "$part" "$dest" $options
		echo "ok: mounted $dest"
	elif [ -z "$(echo $found | grep \"$dest\" || true)" ]
	then
		echo "ok: $dest already mounted"
	else
		echo "partition $part already mounted" >&2
		exit 1
	fi
}

doMount efi
doMount linux
