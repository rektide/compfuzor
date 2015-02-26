#!/bin/bash

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	CSD="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$CSD/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
CSD="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

SUBVOLUMES=$*
if [ -z "$SUBVOLUMES" ]
then
	. $CSD/../env
fi

# Dry-run safety-check
for v in ${SUBVOLMES[@]}
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

for v in ${SUBVOLUMES[@]}
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

	[ "$bak" != 0 ] && mv $v.bak/* $v/ && rm -r $v.bak
done
