#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	CSD="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$CSD/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CSD="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

[ -z "$BTRFS_ROOT_SUBVOLUME" ] && . "$CSD/../env"
[ -z "$BTRFS_ROOT_SUBVOLUME" ] && exit 1

[ -z "$TARGET" ] && TARGET="."

cd "$TARGET"
[ ! -e $(dirname $BTRFS_ROOT_SUBVOLUME) ] && mkdir -p "$(dirname $BTRFS_ROOT_SUBVOLUME)"
$CSD/test-subvol.sh "$BTRFS_ROOT_SUBVOLUME" || btrfs subvolume create "$BTRFS_ROOT_SUBVOLUME"

SUBVOL_ID=$(btrfs subvolume list -p . | grep "$BTRFS_ROOT_SUBVOLUME" | cut -d' ' -f2)
re='^[0-9]+$'
if ! [[ $SUBVOL_ID =~ $re ]] ; then
	echo "error: did not get a subvolume id" >&2
	exit 2
fi
btrfs subvolume set-default $SUBVOL_ID .
