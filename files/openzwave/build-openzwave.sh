#!/bin/sh

cd {{DIR}}
export PREFIX="{{OPT}}"
export LIBDIR="{{OPT}}/lib"

make
make install
