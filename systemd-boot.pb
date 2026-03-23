---
- hosts: all
  vars:
    BINS:
    # distro bundles a solution now
    #- name: zz-update-systemd-boot
    #LINKS:
    #  "/etc/kernel/postinst.d/zz-update-systemd-boot": "{{BINS_DIR}}/zz-update-systemd-boot"
  tasks:
    - import_tasks: tasks/compfuzor.includes type=etc
