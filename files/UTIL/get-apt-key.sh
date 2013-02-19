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
TMP_KEYRING=`mktemp --suffix=-get-apt-key`
echo Fetching $KEY from $KEYSERVER to $KEY.gpg

gpg --keyserver $KEYSERVER --no-default-keyring --keyring $TMP_KEYRING --recv-keys $KEY
# would that I understand why the retrieved key is not $KEY, or know what in general was desired to augment --export with desired target
# gpg -a --export --keyring $TMP_KEYRING > $NAME.gpg
gpg -a --export --keyring $TMP_KEYRING > $NAME.gpg
rm $TMP_KEYRING

