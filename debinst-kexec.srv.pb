---
- hosts: all
  vars:
    TYPE: debinst-kexec
    INSTANCE: main
    BINS_RUN_BYPASS: True

    PKGSET:
    PKGS:
      - kexec-tools

    ENV:
      SUITE: "{{ APT_DISTRIBUTION|default(APT_DEFAULT_DISTRIBUTION, true) }}"
      DEBIAN_MIRROR_URI: "{{ APT_MIRROR|default(APT_DEFAULT_MIRROR, true) }}"
      INSTALLER_ARCH: "{{ APT_ARCH|default('amd64', true) }}"
      INSTALLER_BASE_URL: "{{ ENV.DEBIAN_MIRROR_URI }}/dists/{{ ENV.SUITE }}/main/installer-{{ ENV.INSTALLER_ARCH }}/current/images/netboot/debian-installer/{{ ENV.INSTALLER_ARCH }}"
      INSTALLER_KERNEL: linux
      INSTALLER_INITRD: initrd.gz
      INSTALLER_PRESEED_URL: ""
      INSTALLER_CMDLINE: ""
      INSTALLER_CMDLINE_EXTRA: ""
      INSTALLER_AUTO: "0"
      INSTALLER_PRIORITY: ""
      INSTALLER_LOCALE: ""
      INSTALLER_KEYMAP: ""
      INSTALLER_CONSOLES: "tty0 ttyS0,115200n8"
      INSTALLER_FORCE_LEGACY_IFNAMES: "1"
      INSTALLER_KERNEL_QUIET: "0"
      INSTALLER_IPV6_DISABLE: "0"
      INSTALLER_INTERFACE: ""
      INSTALLER_LINK_WAIT_TIMEOUT: ""
      INSTALLER_DHCP_TIMEOUT: ""
      INSTALLER_DHCPV6_TIMEOUT: ""
      INSTALLER_DHCP_HOSTNAME: ""
      INSTALLER_DHCP_FAILED_MANUAL: "0"
      INSTALLER_DHCP_MANUAL_OPTION: "Configure network manually"

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

      INSTALLER_NET_PROFILE: ""
      INSTALLER_NET_SELECTED: "{{ ENV.INSTALLER_NET_PROFILES[ENV.INSTALLER_NET_PROFILE] if (ENV.INSTALLER_NET_PROFILE|default('', true) and ENV.INSTALLER_NET_PROFILE in ENV.INSTALLER_NET_PROFILES) else {} }}"
      INSTALLER_IP_MODE: dhcp
      INSTALLER_IFACE: "{{ ENV.INSTALLER_INTERFACE|default(ENV.INSTALLER_NET_SELECTED.iface, true)|default('') }}"
      INSTALLER_STATIC_ADDRESS: "{{ ENV.INSTALLER_NET_SELECTED.address|default('') }}"
      INSTALLER_STATIC_GATEWAY: "{{ ENV.INSTALLER_NET_SELECTED.gateway|default('') }}"
      INSTALLER_STATIC_NETMASK: "{{ ENV.INSTALLER_NET_SELECTED.netmask|default('') }}"
      INSTALLER_STATIC_HOSTNAME: "{{ ENV.INSTALLER_NET_SELECTED.hostname|default(inventory_hostname|default('debian-installer')) }}"
      INSTALLER_DOMAIN: ""
      INSTALLER_STATIC_DNS1: "{{ ENV.INSTALLER_NET_SELECTED.dns1|default('') }}"
      INSTALLER_STATIC_DNS2: "{{ ENV.INSTALLER_NET_SELECTED.dns2|default('') }}"
      INSTALLER_STATIC_NAMESERVERS: ""
      INSTALLER_NETCFG_CONFIRM_STATIC: "1"
      INSTALLER_NETCFG_DISABLE_AUTOCONFIG: "1"
      INSTALLER_NETCFG_ENABLE: "1"
      INSTALLER_NETCFG_GET_HOSTNAME: "{{ ENV.INSTALLER_STATIC_HOSTNAME }}"
      INSTALLER_NETCFG_GET_DOMAIN: "{{ ENV.INSTALLER_DOMAIN }}"
      INSTALLER_NETCFG_FORCE_HOSTNAME: ""

      INSTALLER_ENABLE_NETCONSOLE: "1"
      INSTALLER_AUTHORIZED_KEYS_URL: ""
      INSTALLER_NETCONSOLE_PASSWORD_DISABLED: "1"
      INSTALLER_NETCONSOLE_PASSWORD: ""

    GET_URLS:
      - url: "{{ ENV.INSTALLER_BASE_URL }}/{{ ENV.INSTALLER_KERNEL }}"
        dest: "{{ ENV.INSTALLER_KERNEL }}"
      - url: "{{ ENV.INSTALLER_BASE_URL }}/{{ ENV.INSTALLER_INITRD }}"
        dest: "{{ ENV.INSTALLER_INITRD }}"

    ETC_FILES:
      - name: nasu.env
        content: |
          # Debian installer options profile for nasu
          INSTALLER_NET_PROFILE=nasu
          INSTALLER_IP_MODE=static
          INSTALLER_IFACE=eth0
          INSTALLER_STATIC_ADDRESS=107.174.69.227
          INSTALLER_STATIC_GATEWAY=107.174.69.1
          INSTALLER_STATIC_NETMASK=255.255.255.0
          INSTALLER_STATIC_DNS1=8.8.8.8
          INSTALLER_STATIC_DNS2=8.8.4.4
          INSTALLER_STATIC_HOSTNAME=nasu
          INSTALLER_DOMAIN=
          INSTALLER_NETCFG_ENABLE=1
          INSTALLER_NETCFG_DISABLE_AUTOCONFIG=1
          INSTALLER_NETCFG_CONFIRM_STATIC=1
          INSTALLER_LINK_WAIT_TIMEOUT=10
          INSTALLER_DHCP_TIMEOUT=60
          INSTALLER_DHCPV6_TIMEOUT=60
          INSTALLER_FORCE_LEGACY_IFNAMES=1
          INSTALLER_CONSOLES="tty0 ttyS0,115200n8"
          INSTALLER_ENABLE_NETCONSOLE=1
          INSTALLER_AUTHORIZED_KEYS_URL=
          INSTALLER_CMDLINE_EXTRA=
          # Optional unattended mode:
          # INSTALLER_AUTO=1
          # INSTALLER_PRIORITY=critical

    BINS:
      - name: installer-kernel-cmdline.sh
        content: |
          # Build Debian installer kernel options and print them.
          # The script uses env->key maps for most netcfg values.
          # You can append arbitrary extra options using INSTALLER_CMDLINE_EXTRA.
          #
          # Usage:
          #   installer-kernel-cmdline.sh [env-file]
          #
          # If env-file is provided, it is sourced first. This is useful for
          # profile files such as etc/nasu.env.

          PROFILE_ENV="${1:-}"
          if [ -n "$PROFILE_ENV" ]; then
            if [ ! -f "$PROFILE_ENV" ]; then
              echo "Error: env file not found: $PROFILE_ENV" >&2
              exit 1
            fi
            # shellcheck source=/dev/null
            . "$PROFILE_ENV"
          fi

          is_true() {
            case "${1:-}" in
              1|true|TRUE|yes|YES|on|ON) return 0 ;;
              *) return 1 ;;
            esac
          }

          ip_address_part() {
            addr="${1:-}"
            case "$addr" in
              \[*\])
                addr="${addr#\[}"
                addr="${addr%\]}"
                ;;
            esac
            addr="${addr%%/*}"
            printf '%s' "$addr"
          }

          escape_cmdline_value() {
            val="${1:-}"
            val="${val//\\/\\\\}"
            val="${val// /\\ }"
            printf '%s' "$val"
          }

          append_raw() {
            [ -n "${1:-}" ] || return 0
            append="$append $1"
          }

          append_kv() {
            key="${1:-}"
            raw="${2:-}"
            [ -n "$key" ] || return 0
            [ -n "$raw" ] || return 0
            append="$append $key=$(escape_cmdline_value "$raw")"
          }

          append_bool_kv() {
            key="${1:-}"
            raw="${2:-}"
            [ -n "$key" ] || return 0
            [ -n "${raw+x}" ] || return 0
            if is_true "$raw"; then
              append="$append $key=true"
            else
              append="$append $key=false"
            fi
          }

          append_console_list() {
            list="${1:-}"
            while [ -n "$list" ]; do
              console="${list%% *}"
              if [ "$console" = "$list" ]; then
                list=""
              else
                list="${list#* }"
                while [ "${list# }" != "$list" ]; do
                  list="${list# }"
                done
              fi

              [ -n "$console" ] || continue
              append_kv "console" "$console"
            done
          }

          get_var_value() {
            var_name="${1:-}"
            [ -n "$var_name" ] || return 0
            eval "printf '%s' \"\${$var_name-}\""
          }

          is_var_set() {
            var_name="${1:-}"
            [ -n "$var_name" ] || return 1
            eval '[ "${'"$var_name"'+x}" = x ]'
          }

          append_kv_map() {
            map="$1"
            var_name="${map%%:*}"
            key_name="${map#*:}"
            var_value="$(get_var_value "$var_name")"
            append_kv "$key_name" "$var_value"
          }

          append_bool_kv_map() {
            map="$1"
            var_name="${map%%:*}"
            key_name="${map#*:}"
            if is_var_set "$var_name"; then
              append_bool_kv "$key_name" "$(get_var_value "$var_name")"
            fi
          }

          append="${INSTALLER_CMDLINE:-}"
          append="${append% ---}"
          append="${append%---}"

          if is_true "${INSTALLER_AUTO:-0}"; then
            append_raw "auto=true"
          fi
          append_kv "priority" "${INSTALLER_PRIORITY:-}"
          append_kv "locale" "${INSTALLER_LOCALE:-}"
          append_kv "keyboard-configuration/xkb-keymap" "${INSTALLER_KEYMAP:-}"
          append_kv "url" "${INSTALLER_PRESEED_URL:-}"

          append_console_list "${INSTALLER_CONSOLES:-}"

          if is_true "${INSTALLER_FORCE_LEGACY_IFNAMES:-0}"; then
            append_raw "net.ifnames=0"
            append_raw "biosdevname=0"
          fi

          if is_true "${INSTALLER_KERNEL_QUIET:-0}"; then
            append_raw "quiet"
          fi

          if is_true "${INSTALLER_IPV6_DISABLE:-0}"; then
            append_raw "ipv6.disable=1"
          fi

          NETCFG_KV_MAP=(
            "INSTALLER_IFACE:netcfg/choose_interface"
            "INSTALLER_LINK_WAIT_TIMEOUT:netcfg/link_wait_timeout"
            "INSTALLER_DHCP_TIMEOUT:netcfg/dhcp_timeout"
            "INSTALLER_DHCPV6_TIMEOUT:netcfg/dhcpv6_timeout"
            "INSTALLER_DHCP_HOSTNAME:netcfg/dhcp_hostname"
            "INSTALLER_NETCFG_GET_HOSTNAME:netcfg/get_hostname"
            "INSTALLER_NETCFG_GET_DOMAIN:netcfg/get_domain"
            "INSTALLER_NETCFG_FORCE_HOSTNAME:netcfg/hostname"
          )

          for map in "${NETCFG_KV_MAP[@]}"; do
            append_kv_map "$map"
          done

          NETCFG_BOOL_MAP=(
            "INSTALLER_NETCFG_ENABLE:netcfg/enable"
            "INSTALLER_NETCFG_DISABLE_AUTOCONFIG:netcfg/disable_autoconfig"
            "INSTALLER_NETCFG_CONFIRM_STATIC:netcfg/confirm_static"
          )

          for map in "${NETCFG_BOOL_MAP[@]}"; do
            append_bool_kv_map "$map"
          done

          if [ -n "${INSTALLER_STATIC_HOSTNAME:-}" ]; then
            append_kv "hostname" "${INSTALLER_STATIC_HOSTNAME}"
          fi
          append_kv "domain" "${INSTALLER_DOMAIN:-}"

          static_addr="$(ip_address_part "${INSTALLER_STATIC_ADDRESS:-}")"
          static_gateway="$(ip_address_part "${INSTALLER_STATIC_GATEWAY:-}")"
          static_netmask="${INSTALLER_STATIC_NETMASK:-}"
          static_host="${INSTALLER_STATIC_HOSTNAME:-debian-installer}"
          static_iface="${INSTALLER_IFACE:-eth0}"

          nameservers="${INSTALLER_STATIC_NAMESERVERS:-}"
          if [ -z "$nameservers" ]; then
            if [ -n "${INSTALLER_STATIC_DNS1:-}" ]; then
              nameservers="$(ip_address_part "${INSTALLER_STATIC_DNS1}")"
            fi
            if [ -n "${INSTALLER_STATIC_DNS2:-}" ]; then
              dns2="$(ip_address_part "${INSTALLER_STATIC_DNS2}")"
              nameservers="${nameservers:+$nameservers }${dns2}"
            fi
          fi

          case "${INSTALLER_IP_MODE:-dhcp}" in
            dhcp)
              if [ -n "${INSTALLER_IFACE:-}" ]; then
                append_raw "ip=:::::${INSTALLER_IFACE}:dhcp"
              else
                append_raw "ip=dhcp"
              fi
              ;;
            static)
              if [ -z "$static_addr" ] || [ -z "$static_gateway" ] || [ -z "$static_netmask" ]; then
                echo "Error: static mode requires INSTALLER_STATIC_ADDRESS, INSTALLER_STATIC_GATEWAY, INSTALLER_STATIC_NETMASK" >&2
                exit 1
              fi

              append_raw "ip=${static_addr}::${static_gateway}:${static_netmask}:${static_host}:${static_iface}:none"
              append_kv "netcfg/get_ipaddress" "$static_addr"
              append_kv "netcfg/get_netmask" "$static_netmask"
              append_kv "netcfg/get_gateway" "$static_gateway"
              append_kv "netcfg/get_nameservers" "$nameservers"
              ;;
            none)
              ;;
            *)
              echo "Error: INSTALLER_IP_MODE must be dhcp, static, or none" >&2
              exit 1
              ;;
          esac

          if is_true "${INSTALLER_DHCP_FAILED_MANUAL:-0}"; then
            append_kv "netcfg/dhcp_failed" "note"
            append_kv "netcfg/dhcp_options" "${INSTALLER_DHCP_MANUAL_OPTION:-Configure network manually}"
          fi

          if is_true "${INSTALLER_ENABLE_NETCONSOLE:-0}"; then
            append_kv "anna/choose_modules" "network-console"
            append_kv "network-console/authorized_keys_url" "${INSTALLER_AUTHORIZED_KEYS_URL:-}"
            if is_true "${INSTALLER_NETCONSOLE_PASSWORD_DISABLED:-1}"; then
              append_kv "network-console/password-disabled" "true"
            else
              append_kv "network-console/password" "${INSTALLER_NETCONSOLE_PASSWORD:-}"
            fi
          fi

          append_raw "${INSTALLER_CMDLINE_EXTRA:-}"

          append="${append# }"
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
