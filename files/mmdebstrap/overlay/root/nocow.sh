#!/bin/sh

target="$*"
[ -n "$target" ] || target=/var/log

chattr -R -c $target
chattr -R +C $target
