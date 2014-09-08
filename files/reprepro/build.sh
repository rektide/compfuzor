#!/bin/sh

set -e
cd "{{DIR}}"
. ./env

reprepro -Vb . export
reprepro -Vb . createsymlinks

#sudo chgrp www-data $(readlink var) -R
