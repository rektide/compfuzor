#!/bin/sh

set -e

export ARCH="{{ARCH}}"

# VARIABLES:
# QEMU - use this qemu (or false. defaults to qemu-arm-static)
# CLEAN - clean up after (or false. defaults to true)
# PRESEED_FILE - preseed file (defaults to etc/preseed)
# POSTPREP - run this script after

#### Configure ####

# where are we writing to
FILE="$1"
if test -z "$FILE" ; then
	FILE=multistrap.tgz
fi
if test ! -e "$FILE" ; then
	echo "specify a file or directory to post process"
	exit 1
elif test -f "$FILE" ; then
	DIR=`mktemp --suffix=.multistrap -d --tmpdir=.`
	tar -C "$DIR" -xzf "$FILE"
else
	DIR="$FILE"
	CLEANUP=false
fi

# preseed
if test -z "$PRESEED_FILE" ; then
	PRESEED_FILE="etc/preseed"
fi
if test "$PRESEED_FILE" = "false" ; then
	true
elif test ! -f "$PRESEED_FILE" ; then
	echo "preseed file ($PRESEED_FILE) does not exist"
	exit 2
else
	PRESEED=`cat $PRESEED_FILE`
fi

# do we need a qemu?
if test -n "$QEMU" ; then
	echo QEMU variable set
elif test "$QEMU" = "false" -o "$ARCH" = "amd64" -o "$ARCH" = "i386" ; then
	QEMU=""
elif test -n "$2" ; then
	QEMU="qemu-$2-static"
else
	QEMU="qemu-arm-static"
fi
if test -n "$QEMU" ; then
	cp /usr/bin/$QEMU "$DIR/usr/bin/"
fi

# absolutize postprep
if test -n "$POSTPREP" ; then
	POSTPREP=`readlink -f $POSTPREP`
fi


#### Really start doing stuff ####

# pushd dir
OLD_DIR=`pwd`
cd $DIR

# bindmounts
sudo mount --bind /proc proc
sudo mount --bind /dev dev

# preseed
echo "$PRESEED" | sudo chroot . /bin/dash -x

# postprep
if test -n "$POSTPREP" ; then
	`$POSTPREP`
fi

#### Cleanup ####

sleep 1

# unmount
sudo umount -l proc
sudo umount -l dev

# cleanup QEMU
if test -n "$QEMU" ; then
	rm "usr/bin/$QEMU"
fi

# popd
cd "$OLD_DIR"

# create tar & cleanup
if test "$CLEANUP" != "false"; then
	sleep 1
	tar --one-file-system -czf "$FILE" -C "$DIR" .
	rm -r "$DIR"; echo $?
fi
