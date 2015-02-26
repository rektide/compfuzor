#!/bin/bash

set -x

TARGET="$PWD"
[ -n "$1" ] && TARGET="$1"

TARGET=$(readlink -f $TARGET)
MOUNT=$(df -P $TARGET|tail -1|tr -s ' '|cut -d' ' -f6)
[[ "$MOUNT" == "$TARGET" ]] && exit

IFS=$'\n'
declare -a SUBVOLS
SUBVOLS=($(btrfs subvolume list -p .|cut -d' ' -f11))
unset IFS

for subvol in ${SUBVOLS[*]}
do
	attempt="${mount}/${subvol}"
	echo "COMPARE ${TARGET} ${attempt}"
	[[ "$TARGET" == "$attempt" ]] && exit
done
exit 1
