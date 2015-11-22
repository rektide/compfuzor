#!/bin/sh

set -e

. $(dirname $(readlink -f $0))/mnt.env
. $(dirname $(readlink -f $0))/var.env

if [ -z "${IMAGE}" ]
then
	if [ -z "$3" -a -f "$2" ]
	then
		IMAGE="$2"
	elif [ -n "$3" ]
	then
		IMAGE="$2"
	else
		IMAGE="${VAR}/pdebuild-cross.tgz"
	fi
fi

# copy configured image on to sd card
(cd $MNT; tar -xzf "${IMAGE}")

[ "$HAD_MNT" = "false" ] && sudo umount "${MNT}" && rm -rf "${MNT}"
