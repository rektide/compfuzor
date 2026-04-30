: "${KERNEL_SYSFS_JSON:?KERNEL_SYSFS_JSON is required}"

sudo systemd-tmpfiles --create "/etc/tmpfiles.d/{{ NAME }}.conf"
