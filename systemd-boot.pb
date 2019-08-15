---
- hosts: all
  vars:
    TYPE: systemd-boot
    INSTANCE: main
    BINS:
    - name: zz-update-systemd-boot
    LINKS:
      "/etc/kernel/postinst.d/zz-update-systemd-boot": "{{BINS_DIR}}/zz-update-systemd-boot"
  tasks:
  - include: tasks/compfuzor.includes type=etc
