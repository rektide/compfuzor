#!/bin/zsh

set -x
set -e

# originally:
#sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 94558F59

# derived:
#gpg --keyserver keyserver.ubuntu.com --export 94558F59 > trusted.gpg.d/spotify.key
#gpg --no-default-keyring --keyring
#--keyserver keyserver.ubuntu.com --export 94558F59 > trusted.gpg.d/spotify.key

# getting a public keyring
# https://stackoverflow.com/questions/51300627/apt-rejects-keyrings-in-etc-apt-trusted-gpg-d-on-ubuntu-18-04


NAME=$1
KEY=$2
KEYSERVER=$3
#[[ -z "$KEYSERVER" ]] && KEYSERVER=keyserver.ubuntu.com
[[ -z "$KEYSERVER" ]] && KEYSERVER=keys.gnupg.net
echo Fetching key $KEY into $NAME.gpg

tmp=`pwd`/$NAME.gpg.tmp
gpg --no-default-keyring --keyring $tmp --keyserver $KEYSERVER --recv-keys $KEY
gpg --no-default-keyring --keyring $tmp --export > $NAME.gpg

#rm $NAME.gpg~
