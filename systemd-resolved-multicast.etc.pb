---
- hosts: all
  vars:
    TYPE: systemd-resolved-multicast
    INSTANCE: main
    ETC_FILES:
      - name: resolved-multicast.conf.d
        content: |
          [Resolved]
          MulticastDNS=yes
      - name: 50-multicast.network
        content: |
          [Match]
          Name=
  tasks:
    - import_tasks: tasks/compfuzor.includes
