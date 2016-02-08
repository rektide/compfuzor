#!/bin/sh

. {{DIR}}/env


# https://github.com/pfalcon/esp-open-sdk#building
cd {{DIR}}/repo/esp-open-sdk
echo Making esp-open-sdk
make STANDALONE=n

cd {{DIR}}/repo/firmware
echo Making nodemcu-firmware
make

cd {{DIR}}/repo/esptool
echo Installing esptool flasher
python setup.py install


#cd {{DIR}}/repo/rsyntaxtextarea
#echo Building rSyntaxTextArea
#./gradlew build

#cd {{DIR}}/repo/esplorer/ESPlorer
#echo Building ESPlorer
#ant
