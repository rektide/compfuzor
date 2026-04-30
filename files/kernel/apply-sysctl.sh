: "${KERNEL_SYSCTL_JSON:?KERNEL_SYSCTL_JSON is required}"

sudo sysctl -p "/etc/sysctl.d/{{ NAME }}.conf"
