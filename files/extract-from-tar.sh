#!/bin/bash

set -e

FILES=`tar -ztf "$1" | egrep "$2"`
while read -r FILE
do
	# Tar is awful. Bash is awful. Everything is awful.
	BASE=`dirname $FILE`
	OLD_IFS="${IFS}"
	IFS=/ COMPONENTS=( $BASE )
	IFS=${OLD_IFS}
	STRIP_COUNT="${#COMPONENTS[@]}"

	echo "$BASE"
	tar -xf "$1" "$FILE" --strip-components ${STRIP_COUNT}
done <<< "$FILES"
