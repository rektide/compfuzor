#!/bin/sh

set -e

cd "{{DIR}}"

source reprepro.env

reprepro -Vb . export
reprepro -Vb . createsymlinks
