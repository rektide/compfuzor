: "${KERNEL_SYSCTL_JSON:?KERNEL_SYSCTL_JSON is required}"

"$DIR/bin/build-kernel-sysctl.sh"

sudo mkdir -p /etc/sysctl.d
sudo ln -sf "$DIR/etc/kernel.sysctl.conf" "/etc/sysctl.d/{{ NAME }}.conf"
