---
- hosts: all
  gather_facts: False
  vars:
    TYPE: btrfs
    INSTANCE: main
    SUBVOLUMES:
    - "{{OPTS_DIR}}"
    - "{{SRVS_DIR}}"
    - "{{SRCS_DIR}}"
    - "{{LOGS_DIR}}"
    - "{{ETCS_DIR}}"
    BINS:
    - subvolumize.sh
    - rootfs.sh
    - test-subvol.sh
  tasks:
  - include: tasks/compfuzor.includes type="opt"
