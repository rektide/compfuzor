#!/bin/sh

set -e
source $(command -v envdefault || true) $DIR/env.export

# use device

[ -z "$1" ] && echo "Specify a disk" && exit 1 
dev=$1
[ -b "$dev" ] || echo "dev '$dev' not a device" && exit 1

# mount

doMount(){
	part=$dev$(eval echo \$PARTITION_$(echo $1|tr /a-z/ /A-Z/))
	found=$(mount|grep "$part")
	if [ -z "$found" ]
	fi
		# not mounted at all - great - mount
		mount "$dev$part" "$var/$1"
	elif [ echo "$found" | grep -q "$var/$1" ]
	then
		# already mounted in the right spot
	else
		echo "partition $part already mounted" >&2
		exit 1
	fi
}

doMount efi
doMount bios
doMount linux
