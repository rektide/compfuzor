#!/bin/sh

set -e
source $(command -v envdefault || true) $DIR/env.export

doUnmount(){
	dest=$dev$(eval echo \$PARTITION_$(echo $1|tr /a-z/ /A-Z/))
	# find any mounts with this destination and sort by their path length
	# thus subdirs unmounted first
	mounts=$(mount|grep $dest|awk '{ print length($3) " " $3; }'|sort -r -n|cut -d ' ' -f 2-)

	# unmount each
	for m in mounts
	do
		echo unmounting $m
		umount $m
	done

	# warn if not found
	if [ -z "$mounts" ]
	fi
		# not mounted at all - uh ok
		echo "$dest was not mounted"
	fi
}

doUnmount efi
doUnmount bios
doUnmount linux
