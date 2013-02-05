# Allow usbseat to override the config
if [ -f /etc/gdm/gdm-usbseat.conf ]; then
	for usbseat in /dev/usbseat/*; do
		seatid=${usbseat##*/}
		if [ -e "/dev/usbseat/$seatid/keyboard" -a -e "/dev/usbseat/$seatid/mouse" -a -e "/dev/usbseat/$seatid/display" ]; then
			CONFIG_FILE="--config=/etc/gdm/gdm-usbseat.conf"
		fi
	done
fi
