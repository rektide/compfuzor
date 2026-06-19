---
# Generates sunshine's `csrf_allowed_origins` from the host's current local
# IP addresses. Two-phase: config.sh writes a static intermediary file into
# {{DIR}}/etc/, then install-user.sh injects it via block-in-file so the
# block stays idempotent and re-runnable when the network changes.
#
# WAN exclusion: range-checked against loopback, RFC1918, link-local, and
# CGNAT (100.64/10, Tailscale's default range). Docker bridges (docker0,
# br-*, veth*, virbr*) are skipped at the interface level since their
# 172.17.x.x addresses live inside RFC1918's 172.16/12 and can't be told
# apart from real LAN ranges by address alone.
- hosts: all
  vars:
    TYPE: sunshine
    INSTANCE: csrf
    BINS:
      - name: config.sh
        basedir: False
        content: |
          #!/bin/bash
          set -euo pipefail

          # Intermediary file consumed by install-user.sh's block-in-file call.
          # Re-run this whenever the host's network changes (DHCP lease, VPN, etc).
          OUT="${ETC_FILE:-{{DIR}}/etc/csrf_allowed_origins.conf}"
          mkdir -p "$(dirname "$OUT")"

          # IPv4 dotted-quad -> 32-bit integer for CIDR range math.
          ip2int() {
            local a b c d
            IFS=. read -r a b c d <<< "$1"
            echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
          }

          # True if $1 sits in a private/local IPv4 range:
          #   127.0.0.0/8     loopback
          #   10.0.0.0/8      RFC1918
          #   192.168.0.0/16  RFC1918
          #   169.254.0.0/16  link-local
          #   172.16.0.0/12   RFC1918
          #   100.64.0.0/10   CGNAT (Tailscale default)
          is_local_ipv4() {
            local n; n=$(ip2int "$1")
            if (( (n & 0xFF000000) == (127 << 24) )); then return 0; fi
            if (( (n & 0xFF000000) == (10  << 24) )); then return 0; fi
            if (( (n & 0xFFFF0000) == ((192 << 24) | (168 << 16)) )); then return 0; fi
            if (( (n & 0xFFFF0000) == ((169 << 24) | (254 << 16)) )); then return 0; fi
            if (( n >= ((172 << 24) | (16  << 16)) && n <= ((172 << 24) | (31  << 16) | 0xFFFF) )); then return 0; fi
            if (( n >= ((100 << 24) | (64  << 16)) && n <= ((100 << 24) | (127 << 16) | 0xFFFF) )); then return 0; fi
            return 1
          }

          has_origin() {
            local needle="$1" o
            for o in "${origins[@]}"; do [ "$o" = "$needle" ] && return 0; done
            return 1
          }

          # Sunshine hard-codes these as defaults, but listing them explicitly
          # keeps the generated config self-documenting.
          origins=(
            "https://localhost"
            "https://127.0.0.1"
            "https://[::1]"
          )

          # Walk IPv4 addresses, skipping container/veth interfaces and any
          # address outside the private ranges above.
          while read -r ip; do
            [ -n "$ip" ] || continue
            is_local_ipv4 "$ip" || continue
            entry="https://$ip"
            has_origin "$entry" || origins+=("$entry")
          done < <(
            ip -4 addr show | awk '
              /^[0-9]+:/ {
                iface=$2; sub(/:$/,"",iface)
                skip=(iface ~ /^(docker|br-|veth|virbr)/)
                next
              }
              !skip && /^[[:space:]]*inet / { sub(/\/.*/,"",$2); print $2 }
            '
          )

          {
            echo 'csrf_allowed_origins = ['
            for o in "${origins[@]}"; do
              printf '    "%s",\n' "$o"
            done | sed '$ s/,$//'
            echo ']'
          } > "$OUT"

          echo "wrote ${#origins[@]} origins to $OUT"
      - name: install-user.sh
        basedir: False
        run: true
        content: |
          #!/bin/bash
          set -euo pipefail

          SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
          "$SCRIPT_DIR/config.sh"

          CONF="${SUNSHINE_CONF:-$HOME/.config/sunshine/sunshine.conf}"
          mkdir -p "$(dirname "$CONF")"
          [ -f "$CONF" ] || touch "$CONF"

          block-in-file \
            --name sunshine-csrf-origins \
            --comment "#" \
            --create file \
            --input "{{DIR}}/etc/csrf_allowed_origins.conf" \
            --output "$CONF"

          echo "injected sunshine-csrf-origins block into $CONF"
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
