#!/bin/bash

# what kind of cruftacular old world ant bullshit is this?

# POM is property versioned, but the build artifacts dont reflect any such thing.
# You clearly don't give half a crap about actually producing usable maven artifacts do you?

# awful, misery inducing junk. you suck.

BUILD="{{DIR}}/build"
VERSION="{{version}}"

for MODULE in all generator library core integration parent
do
	mvn install:install-file -Dfile=$BUILD/maven-bundle-hamcrest-$MODULE.jar -DpomFile=$BUILD/hamcrest-$MODULE-$VERSION.pom
done
