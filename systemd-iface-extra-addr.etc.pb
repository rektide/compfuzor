---
# systemd-iface-extra-addr: add a STATIC secondary IPv4 address to an
# interface whose DHCP lease stays authoritative (default route, DNS, etc.
# all keep coming from DHCP). This is the stable anchor a kube node-IP pin
# points at (k3s.srv.pb NODE_IP): embedded-etcd member peer URLs stop
# drifting with DHCP leases while the host remains fully DHCP-mobile.
#
# The address lands as a networkd drop-in
# (/etc/systemd/network/<NETWORK_FILE>.network.d/<NAME>.conf) merged into the
# existing config -- no .network replacement,
# no DHCP disruption -- applied live via `networkctl reload && reconfigure`
# (briefest of address blips; no reboot).
#
# !!! Pick an address OUTSIDE the DHCP pool (or reserve it router-side) !!!
# Two owners of one address is a silent, nasty failure mode.
#
# Inventory-driven deploy example (`NODE_IP_CIDR` lives with k3s_node_ip):
#   ansible-playbook -i ~/.ansible/k3s -c local \
#     systemd-iface-extra-addr.etc.pb --limit workhorse
- hosts: all
  vars:
    TYPE: systemd-iface-extra-addr
    INSTANCE: "{{IFACE}}"

    IFACE: eno1
    # basename (sans .network) of the existing networkd config to extend
    NETWORK_FILE: en
    # SYSTEMD_NETWORK_DIR resolves to systemd's vendor unit directory on
    # this host (/usr/lib/networkd/network). Local administrative overrides
    # belong in /etc/systemd/network instead.
    NETWORKD_CONFIG_DIR: /etc/systemd/network
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
        dest: "{{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d/{{NAME}}.conf"
        policy: replace
        strategies:
          available: [copy]
          default: copy

    BINS:
      - name: apply.sh
        content: |
          #!/bin/sh
          # Apply the drop-in live: reload networkd, reconfigure the iface,
          # verify the address actually landed.
          set -e
          # networkd cannot traverse Compfuzor's private deployment dirs, so
          # LINKS delivers this as a regular copy. Ensure networkd can traverse
          # the drop-in dir and read the copied file before reload.
          sudo install -d -m 0755 {{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d
          sudo chmod 0644 {{NETWORKD_CONFIG_DIR}}/{{NETWORK_FILE}}.network.d/{{NAME}}.conf
          sudo networkctl reload
          sudo networkctl reconfigure {{IFACE}}
          # Reconfigure briefly drops the DHCP lease. Do not report success
          # until both the static address and DHCP-owned default route return.
          ready=false
          for _ in $(seq 1 30); do
            if ip -4 addr show {{IFACE}} | grep -q "{{_addr}}" \
              && ip -4 route show default dev {{IFACE}} | grep -q '^default '; then
              ready=true
              break
            fi
            sleep 1
          done
          if [ "$ready" != true ]; then
            echo "ERROR: {{IFACE}} did not regain both {{_addr}} and its DHCP default route" >&2
            ip -4 -brief addr show {{IFACE}} >&2 || true
            ip -4 route show default dev {{IFACE}} >&2 || true
            exit 1
          fi
          echo "OK: {{_addr}} assigned on {{IFACE}}; DHCP default route restored"
          echo
          ip -4 -brief addr show {{IFACE}}

  tasks:
    - import_tasks: tasks/compfuzor.includes
