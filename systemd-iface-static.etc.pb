---
- hosts: all
  vars:
    TYPE: systemd-iface-static
    INSTANCE: main

    IFACE: eth0
    ADDRESS_CIDR: 216.144.229.17/24
    GATEWAY: 216.144.229.1
    DNS:
      - 8.8.8.8
      - 8.8.4.4

    ETC_FILES:
      - name: iface-static.network
        content: |
          [Match]
          Name={{IFACE}}

          [Network]
          Address={{ADDRESS_CIDR}}
          Gateway={{GATEWAY}}
          {% for dns in DNS|default([]) %}
          DNS={{dns}}
          {% endfor %}

    LINKS:
      "{{SYSTEMD_NETWORK_DIR}}/10-{{IFACE}}-static.network": "{{ETC}}/iface-static.network"

    BINS:
      - name: apply.sh
        content: |
          sudo systemctl enable --now systemd-networkd.service
          sudo systemctl enable --now systemd-resolved.service
          sudo networkctl reload
          sudo networkctl reconfigure {{IFACE}}

  tasks:
    - import_tasks: tasks/compfuzor.includes
