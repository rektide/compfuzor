#!/bin/sh

set -e

# VARIABLES:
# QEMU - use this qemu (or false. defaults to qemu-arm-static)
# CLEAN - clean up after (or false. defaults to true)
# PRESEED_FILE - preseed file (defaults to etc/preseed)
# POSTPREP - run this script after

#### Configure ####

# where are we writing to
FILE="$1"
if test -z "$FILE" ; then
	FILE=pdebuild-cross.tgz
fi
if test ! -e "$FILE" ; then
	echo "specify a file or directory to post process"
	exit 1
elif test -f "$FILE" ; then
	DIR=`mktemp --suffix=.pdebuildx -d --tmpdir=.`
	tar -xzf -C "$DIR" "$FILE"
else
	DIR="$FILE"
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
if test "$QEMU" = "false" ; then
	QEMU=""
elif test -n "$QEMU" ; then
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

# unmount
sudo umount proc
sudo umount dev

# cleanup QEMU
if test -n "$QEMU" ; then
	rm "usr/bin/$QEMU"
fi

# popd
cd "$OLD_DIR"

# create tar & cleanup
if test "$CLEANUP" != "false" ; then
	tar -czf "$FILE" -C "$DIR" .
	rm -r "$DIR"
fi
