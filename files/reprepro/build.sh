#!/bin/sh

set -e

cd "{{DIR}}"

. ./reprepro.env

reprepro -Vb . export
reprepro -Vb . createsymlinks
