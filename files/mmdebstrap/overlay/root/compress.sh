#!/bin/sh
btrfs property set ${1:-$(pwd)} compression zstd
