: "${KERNEL_SYSFS_JSON:?KERNEL_SYSFS_JSON is required}"

"$DIR/bin/build-sysfs.sh"

sudo mkdir -p /etc/tmpfiles.d
sudo ln -sf "$DIR/etc/kernel.tmpfiles.conf" "/etc/tmpfiles.d/{{ NAME }}.conf"
