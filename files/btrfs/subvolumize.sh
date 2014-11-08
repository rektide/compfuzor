#!/bin/zsh

SUBVOLUMES=$*
if [ -n "$SUBVOLUMES" ]
then
	SUBVOLUMES=( {{ SUBVOLUMES|default([])|map('replace', ' ', '\ ')|join(' ') }} )
fi

for v in $SUBVOLUMES
do
	# move existing out of the way
	bak=0
	if [ -e "$v" ]
	then
		if [ -e "$v" ]
		then
			echo "cannot backup $v, .bak already exists"
			exit 1
		fi
		bak=1
		mv $v $v.bak
	fi

	btrfs subvolume 

done
