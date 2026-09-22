---
# systemd-iface-extra-addr: add a STATIC secondary IPv4 address to an
# interface whose DHCP lease stays authoritative (default route, DNS, etc.
# all keep coming from DHCP). This is the stable anchor a kube node-IP pin
# points at (k3s.srv.pb NODE_IP): embedded-etcd member peer URLs stop
# drifting with DHCP leases while the host remains fully DHCP-mobile.
#
# The address lands as a networkd drop-in (SYSTEMD_NETWORK_DIR/<NETWORK_FILE>.d/
# <NAME>.conf) merged into the existing config -- no .network replacement,
# no DHCP disruption -- applied live via `networkctl reload && reconfigure`
# (briefest of address blips; no reboot).
#
# !!! Pick an address OUTSIDE the DHCP pool (or reserve it router-side) !!!
# Two owners of one address is a silent, nasty failure mode.
#
# Deploy example:
#   ansible-playbook -i 'localhost,' -c local systemd-iface-extra-addr.etc.pb \
#     -e ADDRESS_CIDR=192.168.1.8/22
- hosts: all
  vars:
    TYPE: systemd-iface-extra-addr
    INSTANCE: "{{IFACE}}"

    IFACE: eno1
    # basename (sans .network) of the existing networkd config to extend
    NETWORK_FILE: en
    # NODE_IP_CIDR belongs in host inventory beside k3s's NODE_IP so this
    # playbook and k3s.srv.pb cannot drift apart.
    ADDRESS_CIDR: "{{NODE_IP_CIDR|default('192.168.1.8/22')}}"

    _addr: "{{ADDRESS_CIDR.split('/')[0]}}"

    ETC_FILES:
      - name: extra-addr.conf
        content: |
          # static secondary address ({{NAME}}); DHCP stays authoritative
          [Network]
          Address={{ADDRESS_CIDR}}

    LINKS:
      - src: "{{ETC}}/extra-addr.conf"
        dest: "{{SYSTEMD_NETWORK_DIR}}/{{NETWORK_FILE}}.d/{{NAME}}.conf"

    BINS:
      - name: apply.sh
        content: |
          #!/bin/sh
          # Apply the drop-in live: reload networkd, reconfigure the iface,
          # verify the address actually landed.
          set -e
          sudo mkdir -p {{SYSTEMD_NETWORK_DIR}}/{{NETWORK_FILE}}.d
          sudo networkctl reload
          sudo networkctl reconfigure {{IFACE}}
          sleep 2
          if ip -4 addr show {{IFACE}} | grep -q "{{_addr}}"; then
            echo "OK: {{_addr}} assigned on {{IFACE}}"
          else
            echo "ERROR: {{_addr}} not assigned on {{IFACE}}" >&2
            exit 1
          fi
          echo
          ip -4 -brief addr show {{IFACE}}

  tasks:
    - import_tasks: tasks/compfuzor.includes
