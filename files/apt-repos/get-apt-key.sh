#!/bin/zsh

# originally:
#sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 94558F59

# derived:
#gpg --keyserver keyserver.ubuntu.com --export 94558F59 > trusted.gpg.d/spotify.key
#gpg --no-default-keyring --keyring
#--keyserver keyserver.ubuntu.com --export 94558F59 > trusted.gpg.d/spotify.key

NAME=$1
KEY=$2
KEYSERVER=$3
[[ -z "$KEYSERVER" ]] && KEYSERVER=keys.gnupg.net
echo Fetching key $KEY into $NAME.gpg

gpg --no-default-keyring --keyring `pwd`/$NAME.gpg --keyserver $KEYSERVER --recv-keys $KEY
rm $NAME.gpg~
