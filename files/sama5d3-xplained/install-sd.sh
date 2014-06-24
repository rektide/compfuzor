#!/bin/sh

set -e

test -z "$2" && export VAR="{{VAR}}"
test -z "$3" && export IMAGE="${VAR}/pdebuild-cross.tgz"

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

BIN_DIR=$(dirname $(readlink -f $0))
"${BIN_DIR}/part1-install-sd.sh" "${PART1}" "$2" "$3"
"${BIN_DIR}/part2-install-sd.sh" "${PART2}" "$2" "$3"
