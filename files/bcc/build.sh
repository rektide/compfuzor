#!/bin/bash

set -e

[ -z "$DIR" ] && export DIR={{DIR}}
[ -z "$BUILD" ] && export BUILD=$DIR/build
[ -z "$REPO" ] && export REPO=$DIR/repo

[ ! -e "$BUILD" ] && mkdir "$BUILD"
cd "$BUILD"
cmake "$REPO" -DCMAKE_INSTALL_PREFIX="${PREFIX}"
make
sudo make install
