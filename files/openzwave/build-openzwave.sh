#!/bin/sh

cd {{DIR}}
export PREFIX="{{OPT}}"
#export LIBDIR="{{OPT}}/lib"

make
make install
ln -sf {{OPT}}/lib64/* /usr/local/lib
ln -sf {{OPT}}/include/openzwave /usr/local/include
