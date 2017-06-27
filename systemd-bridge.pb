---
- hosts: all
  vars:
    TYPE: bridge
    INSTANCE: main
    ETC_FILES:
    - name: "systemd-bridge.netdev"
    - name: "systemd-bridge.network"
    - name: "systemd-bridge-devices.network"
    LINKS:
     "{{SYSTEMD_NETWORK_DIR}}/{{NAME}}.netdev": "{{ETC}}/systemd-bridge.netdev"
     "{{SYSTEMD_NETWORK_DIR}}/{{NAME}}.network": "{{ETC}}/systemd-bridge.network"
     "{{SYSTEMD_NETWORK_DIR}}/{{NAME}}-devices.network": "{{ETC}}/systemd-bridge-devices.network"
    devices:
    - en*

  tasks:
  - include: tasks/compfuzor.includes type=srv
