#!/bin/sh

set -e

if [ ! -b "${1}" ]
then
	echo Not a block device to instal boot files into
	exit 3
fi

if [ -z "${VAR}" ]
then
	if [ -n "$2" ]
	then
		VAR="$2"
	else
		VAR="{{VAR}}"
	fi
fi

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
ROOT_MNT=`mktemp -d --suffix=root-mnt --tmpdir=.`
OLDD=`pwd`
sudo mount "${1}" "${ROOT_MNT}"
cd "${ROOT_MNT}"
tar -xzf "${IMAGE}"
cd "${OLDD}"
sudo umount "${ROOT_MNT}"
rm -rf "${ROOT_MNT}"
