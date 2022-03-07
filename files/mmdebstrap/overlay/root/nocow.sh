#!/bin/sh

target="$*"
[ -n "$target" ] || target=/var/log/journal

chattr -R -c $target
chattr -R +C $target
