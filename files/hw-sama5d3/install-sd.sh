#!/bin/sh

set -e

[ -z "$2" ] && export VAR="{{VAR}}"
[ -z "$3" ] && export IMAGE="{{IMAGE|default('${VAR}/pdebuild-cross.tgz')}}"
[ -z "$BINS_DIR" ] && export BINS_DIR="{{BINS_DIR}}"

if [ -z "$1" ]
then
	echo "no target specified"
	exit 1
fi
DISK="$1"

PART1="${DISK}1"
PART2="${DISK}2"
if [ ! -b "${PART1}" ]
then
	PART1="${DISK}p1"
	PART2="${DISK}p2"
fi
if [ ! -b "${PART1}" ]
then
	echo "partition not found"
	exit 2
fi

"${BINS_DIR}/part1-install-sd.sh" "${PART1}" "$2" "$3"
"${BINS_DIR}/part2-install-sd.sh" "${PART2}" "$2" "$3"
