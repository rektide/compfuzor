#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	CSD="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$CSD/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CSD="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

BTRFS_SUBVOLUMES=$*
if [ -z "$BTRFS_SUBVOLUMES" ]
then
	. $CSD/../env
fi

# Dry-run safety-check
for v in ${BTRFS_SUBVOLUMES[@]}
do
	if [ -e "$v" ]
	then
		# already a subvolume
		$CSD/test-subvol.sh $v && continue

		if [ -e "$v.bak" ]
		then
			echo "cannot backup $v, .bak already exists"
			exit 1
		fi
	fi

done

for v in ${BTRFS_SUBVOLUMES[@]}
do
	# move existing out of the way
	bak=0
	if [ -e "$v" ]
	then

		# already a subvolume
		$CSD/test-subvol.sh $v && continue

		if [ -e "$v.bak" ]
		then
			echo "cannot backup $v, .bak already exists"
			exit 2
		fi
		bak=2
		mv $v $v.bak
	fi

	mkdir -p $(dirname $v)
	btrfs subvolume create $v

	# copy contents including dotfiles (the /. form), then drop the backup
	[ "$bak" != 0 ] && cp -a "$v.bak/." "$v/" && rm -rf "$v.bak"
done
