---
- hosts: all
  vars:
    TYPE: debinst-kexec
    INSTANCE: main
    BINS_RUN_BYPASS: True

    PKGSET:
    PKGS:
      - kexec-tools

    SUITE: "{{ APT_DISTRIBUTION|default(APT_DEFAULT_DISTRIBUTION, true) }}"
    DEBIAN_MIRROR_URI: "{{ APT_MIRROR|default(APT_DEFAULT_MIRROR, true) }}"
    INSTALLER_ARCH: "{{ APT_ARCH|default('amd64', true) }}"
    INSTALLER_BASE_URL: "{{ DEBIAN_MIRROR_URI }}/dists/{{ SUITE }}/main/installer-{{ INSTALLER_ARCH }}/current/images/netboot/debian-installer/{{ INSTALLER_ARCH }}"
    INSTALLER_KERNEL: linux
    INSTALLER_INITRD: initrd.gz
    INSTALLER_PRESEED_URL: ""
    INSTALLER_CMDLINE: "auto=true priority=critical"
    INSTALLER_CONSOLES: "tty0 ttyS0,115200n8"

    # Network profile examples from ~/doc/if.md
    INSTALLER_NET_PROFILES:
      mithra:
        iface: eth0
        address: 216.144.229.17
        gateway: 216.144.229.1
        netmask: 255.255.255.0
        dns1: 8.8.8.8
        dns2: 8.8.4.4
      nasu:
        iface: eth0
        address: 107.174.69.227
        gateway: 107.174.69.1
        netmask: 255.255.255.0
        dns1: 8.8.8.8
        dns2: 8.8.4.4

    # Set to mithra or nasu to preload example static values.
    INSTALLER_NET_PROFILE: ""
    INSTALLER_NET_SELECTED: "{{ INSTALLER_NET_PROFILES[INSTALLER_NET_PROFILE] if (INSTALLER_NET_PROFILE|default('', true) and INSTALLER_NET_PROFILE in INSTALLER_NET_PROFILES) else {} }}"
    INSTALLER_IP_MODE: dhcp
    INSTALLER_IFACE: "{{ INSTALLER_NET_SELECTED.iface|default('') }}"
    INSTALLER_STATIC_ADDRESS: "{{ INSTALLER_NET_SELECTED.address|default('') }}"
    INSTALLER_STATIC_GATEWAY: "{{ INSTALLER_NET_SELECTED.gateway|default('') }}"
    INSTALLER_STATIC_NETMASK: "{{ INSTALLER_NET_SELECTED.netmask|default('') }}"
    INSTALLER_STATIC_HOSTNAME: "{{ INSTALLER_NET_SELECTED.hostname|default(inventory_hostname|default('debian-installer')) }}"
    INSTALLER_STATIC_DNS1: "{{ INSTALLER_NET_SELECTED.dns1|default('') }}"
    INSTALLER_STATIC_DNS2: "{{ INSTALLER_NET_SELECTED.dns2|default('') }}"

    INSTALLER_ENABLE_NETCONSOLE: "1"
    INSTALLER_AUTHORIZED_KEYS_URL: ""
    INSTALLER_NETCONSOLE_PASSWORD_DISABLED: "1"
    INSTALLER_NETCONSOLE_PASSWORD: ""

    GET_URLS:
      - url: "{{ INSTALLER_BASE_URL }}/{{ INSTALLER_KERNEL }}"
        dest: "{{ INSTALLER_KERNEL }}"
      - url: "{{ INSTALLER_BASE_URL }}/{{ INSTALLER_INITRD }}"
        dest: "{{ INSTALLER_INITRD }}"

    ENV:
      SUITE: "{{ SUITE }}"
      DEBIAN_MIRROR_URI: "{{ DEBIAN_MIRROR_URI }}"
      INSTALLER_ARCH: "{{ INSTALLER_ARCH }}"
      INSTALLER_KERNEL: "{{ INSTALLER_KERNEL }}"
      INSTALLER_INITRD: "{{ INSTALLER_INITRD }}"
      INSTALLER_PRESEED_URL: "{{ INSTALLER_PRESEED_URL|default('', true) }}"
      INSTALLER_CMDLINE: "{{ INSTALLER_CMDLINE }}"
      INSTALLER_CONSOLES: "{{ INSTALLER_CONSOLES }}"
      INSTALLER_IP_MODE: "{{ INSTALLER_IP_MODE }}"
      INSTALLER_IFACE: "{{ INSTALLER_IFACE }}"
      INSTALLER_STATIC_ADDRESS: "{{ INSTALLER_STATIC_ADDRESS }}"
      INSTALLER_STATIC_GATEWAY: "{{ INSTALLER_STATIC_GATEWAY }}"
      INSTALLER_STATIC_NETMASK: "{{ INSTALLER_STATIC_NETMASK }}"
      INSTALLER_STATIC_HOSTNAME: "{{ INSTALLER_STATIC_HOSTNAME }}"
      INSTALLER_STATIC_DNS1: "{{ INSTALLER_STATIC_DNS1 }}"
      INSTALLER_STATIC_DNS2: "{{ INSTALLER_STATIC_DNS2 }}"
      INSTALLER_ENABLE_NETCONSOLE: "{{ INSTALLER_ENABLE_NETCONSOLE }}"
      INSTALLER_AUTHORIZED_KEYS_URL: "{{ INSTALLER_AUTHORIZED_KEYS_URL|default('', true) }}"
      INSTALLER_NETCONSOLE_PASSWORD_DISABLED: "{{ INSTALLER_NETCONSOLE_PASSWORD_DISABLED }}"
      INSTALLER_NETCONSOLE_PASSWORD: "{{ INSTALLER_NETCONSOLE_PASSWORD|default('', true) }}"

    BINS:
      - name: installer-kernel-cmdline.sh
        content: |
          # Build Debian installer kernel options and print them.
          #
          # Options consumed from environment:
          #   INSTALLER_CMDLINE
          #     Base options string. Default: "auto=true priority=critical"
          #     Any trailing "---" is stripped.
          #
          #   INSTALLER_PRESEED_URL
          #     If set, appends: url=<value>
          #
          #   INSTALLER_CONSOLES
          #     Space-separated list of console targets.
          #     For each token, appends: console=<token>
          #     Example: "tty0 ttyS0,115200n8"
          #
          #   INSTALLER_IP_MODE
          #     One of: dhcp | static | none
          #
          #   INSTALLER_IFACE
          #     Interface name for networking.
          #     Used by dhcp mode to force a specific interface and by static mode.
          #
          #   INSTALLER_STATIC_ADDRESS
          #   INSTALLER_STATIC_GATEWAY
          #   INSTALLER_STATIC_NETMASK
          #   INSTALLER_STATIC_HOSTNAME
          #   INSTALLER_STATIC_DNS1
          #   INSTALLER_STATIC_DNS2
          #     Used when INSTALLER_IP_MODE=static.
          #     Required: ADDRESS, GATEWAY, NETMASK.
          #     Optional: HOSTNAME, DNS1, DNS2.
          #
          #   INSTALLER_ENABLE_NETCONSOLE
          #     "1" enables installer network-console module.
          #
          #   INSTALLER_AUTHORIZED_KEYS_URL
          #     If set with netconsole enabled, appends:
          #     network-console/authorized_keys_url=<value>
          #
          #   INSTALLER_NETCONSOLE_PASSWORD_DISABLED
          #     "1" appends: network-console/password-disabled=true
          #
          #   INSTALLER_NETCONSOLE_PASSWORD
          #     Used only when netconsole is enabled and password-disabled != "1".
          #     Appends: network-console/password=<value>

          append="${INSTALLER_CMDLINE:-auto=true priority=critical}"
          append="${append% ---}"
          append="${append%---}"

          if [ -n "${INSTALLER_PRESEED_URL:-}" ]; then
            append="$append url=${INSTALLER_PRESEED_URL}"
          fi

          if [ -n "${INSTALLER_CONSOLES:-}" ]; then
            for console in ${INSTALLER_CONSOLES}; do
              append="$append console=${console}"
            done
          fi

          case "${INSTALLER_IP_MODE:-dhcp}" in
            dhcp)
              if [ -n "${INSTALLER_IFACE:-}" ]; then
                append="$append ip=:::::${INSTALLER_IFACE}:dhcp"
              else
                append="$append ip=dhcp"
              fi
              ;;
            static)
              if [ -z "${INSTALLER_STATIC_ADDRESS:-}" ] || [ -z "${INSTALLER_STATIC_GATEWAY:-}" ] || [ -z "${INSTALLER_STATIC_NETMASK:-}" ]; then
                echo "Error: static mode requires INSTALLER_STATIC_ADDRESS, INSTALLER_STATIC_GATEWAY, INSTALLER_STATIC_NETMASK" >&2
                exit 1
              fi
              host_name="${INSTALLER_STATIC_HOSTNAME:-debian-installer}"
              iface_name="${INSTALLER_IFACE:-eth0}"
              append="$append ip=${INSTALLER_STATIC_ADDRESS}::${INSTALLER_STATIC_GATEWAY}:${INSTALLER_STATIC_NETMASK}:${host_name}:${iface_name}:none"
              if [ -n "${INSTALLER_STATIC_DNS1:-}" ]; then
                append="$append nameserver=${INSTALLER_STATIC_DNS1}"
              fi
              if [ -n "${INSTALLER_STATIC_DNS2:-}" ]; then
                append="$append nameserver=${INSTALLER_STATIC_DNS2}"
              fi
              ;;
            none)
              ;;
            *)
              echo "Error: INSTALLER_IP_MODE must be dhcp, static, or none" >&2
              exit 1
              ;;
          esac

          if [ "${INSTALLER_ENABLE_NETCONSOLE:-0}" = "1" ]; then
            append="$append anna/choose_modules=network-console"
            if [ -n "${INSTALLER_AUTHORIZED_KEYS_URL:-}" ]; then
              append="$append network-console/authorized_keys_url=${INSTALLER_AUTHORIZED_KEYS_URL}"
            fi
            if [ "${INSTALLER_NETCONSOLE_PASSWORD_DISABLED:-1}" = "1" ]; then
              append="$append network-console/password-disabled=true"
            elif [ -n "${INSTALLER_NETCONSOLE_PASSWORD:-}" ]; then
              append="$append network-console/password=${INSTALLER_NETCONSOLE_PASSWORD}"
            fi
          fi

          printf '%s\n' "$append"

      - name: kexec-installer-check.sh
        content: |
          KERNEL="{{SRC}}/${INSTALLER_KERNEL:-linux}"
          INITRD="{{SRC}}/${INSTALLER_INITRD:-initrd.gz}"

          echo "Checking installer artifacts:"
          echo "  kernel: $KERNEL"
          echo "  initrd: $INITRD"

          if [ ! -r "$KERNEL" ] || [ ! -r "$INITRD" ]; then
            echo "Error: missing installer artifacts in {{SRC}}"
            echo "Run this playbook with GET_URLS enabled first."
            exit 1
          fi

          if ! command -v kexec >/dev/null 2>&1; then
            echo "Error: kexec not found (install kexec-tools)"
            exit 1
          fi

          if [ -r /proc/sys/kernel/kexec_load_disabled ]; then
            disabled=$(cat /proc/sys/kernel/kexec_load_disabled)
            if [ "$disabled" != "0" ]; then
              echo "Error: kexec loading disabled (/proc/sys/kernel/kexec_load_disabled=$disabled)"
              exit 1
            fi
          fi

          KERNEL_OPTS="$({{BINS_DIR}}/installer-kernel-cmdline.sh)"
          APPEND="$KERNEL_OPTS ---"

          echo "kexec preflight looks good."
          echo "Load command:"
          echo "  kexec -l $KERNEL --initrd=$INITRD --append=\"$APPEND\""
          echo "Execute command:"
          echo "  systemctl kexec   # or: kexec -e"

      - name: kexec-installer-load.sh
        content: |
          KERNEL="{{SRC}}/${INSTALLER_KERNEL:-linux}"
          INITRD="{{SRC}}/${INSTALLER_INITRD:-initrd.gz}"

          if [ ! -r "$KERNEL" ] || [ ! -r "$INITRD" ]; then
            echo "Error: missing installer artifacts in {{SRC}}"
            exit 1
          fi

          KERNEL_OPTS="$({{BINS_DIR}}/installer-kernel-cmdline.sh)"
          APPEND="$KERNEL_OPTS ---"

          echo "Loading Debian installer into kexec kernel buffer"
          kexec -l "$KERNEL" --initrd="$INITRD" --append="$APPEND"
          echo "Loaded. To boot now: systemctl kexec"

      - name: kexec-installer-exec.sh
        content: |
          "{{BINS_DIR}}/kexec-installer-load.sh"

          echo "Switching into Debian installer via kexec"
          if command -v systemctl >/dev/null 2>&1; then
            systemctl kexec || kexec -e
          else
            kexec -e
          fi

  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv
