#!/bin/sh

#sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 94558F59
#gpg --keyserver keyserver.ubuntu.com --export 94558F59 > trusted.gpg.d/spotify.key
#gpg --no-default-keyring --keyring
#--keyserver keyserver.ubuntu.com --export 94558F59 > trusted.gpg.d/spotify.key

KEY=94558F59 
KEY=082CCEDF94558F59

gpg --keyserver keyserver.ubuntu.com --no-default-keyring --keyring keyrings.d/spotify.keyring --recv-keys $KEY
gpg -a --export $KEY --keyring keyrings.d/spotify.keyring > trusted.gpg.d/spotify.gpg

