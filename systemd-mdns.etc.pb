---
- hosts: all
  vars:
    TYPE: systemd-mdns
    INSTANCE: main
    ETC_FILES:
      - name: systemd-mdns.conf
        content: |
          [Resolve]
          MulticastDNS=yes
    BINS:
      - name: install.sh
        content: |
          sudo mkdir -p /etc/systemd/resolved.conf.d
          sudo ln -sf {{ETC}}/systemd-mdns.conf /etc/systemd/resolved.conf.d/systemd-mdns.conf
  tasks:
    - import_tasks: tasks/compfuzor.includes
