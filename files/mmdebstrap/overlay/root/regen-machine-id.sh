#!/bin/sh

# TODO, try: systemd-firstboot --root=/mnt --setup-machine-id
# DEP: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=844528

rm -f /etc/machine-id /var/lib/dbus/machine-id
dbus-uuidgen --ensure
systemd-machine-id-setup
