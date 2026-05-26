---
- hosts: all
  vars:
    TYPE: systemd-resolved-multicast
    INSTANCE: main
    IFACES: ""
    IFACE_ALL: ""
    ENV:
      - IFACES
      - IFACE_ALL
    ETC_FILES:
      - name: resolved-mdns.conf
        content: |
          [Resolve]
          MulticastDNS=yes
      - name: mdns.conf
        content: |
          [Network]
          MulticastDNS=yes
      - name: multicast.all.conf
        content: |
          [Network]
          MulticastDNS=yes

          [Link]
          Multicast=true
    BINS:
      - name: install-global.sh
        content: |
          sudo mkdir -p /etc/systemd/resolved.conf.d
          sudo ln -sf {{ETC}}/resolved-mdns.conf /etc/systemd/resolved.conf.d/resolved-mdns.conf
      - name: install-iface.sh
        content: |
          IFACES="${IFACES:-{{ IFACES | default('') }}}"
          IFACE_ALL="${IFACE_ALL:-{{ IFACE_ALL | default('') }}}"

          if [ $# -gt 0 ]; then
            TARGETS="$*"
          else
            TARGETS="${IFACES//,/ }"
          fi

          if [ "$IFACE_ALL" = "true" ] || [ "$IFACE_ALL" = "1" ] || [ "$IFACE_ALL" = "yes" ]; then
            DROPIN="multicast.all.conf"
          else
            DROPIN="mdns.conf"
          fi

          for netfile in /etc/systemd/network/*.network; do
            [ -f "$netfile" ] || continue
            base=$(basename "$netfile" .network)

            if [ -z "$TARGETS" ]; then
              match=true
            else
              match=false
              for pattern in $TARGETS; do
                case "$base" in
                  $pattern) match=true; break ;;
                esac
              done
            fi

            if $match; then
              sudo mkdir -p "/etc/systemd/network/$base.network.d"
              sudo ln -sf "{{ETC}}/$DROPIN" "/etc/systemd/network/$base.network.d/$DROPIN"
            fi
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
