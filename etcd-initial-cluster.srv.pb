---
- hosts: all
  tags:
  - etcd
  - etcd-srv
  gather_facts: False
  vars:
    TYPE: etcd
    INSTANCE: main

    VAR_DIR: True
    BIN_DIRS: True
    ETCD_FILES:
    - environment
    SYSTEMD_SERVICE: True

    ENV:
      etcd_discovery: "{{DISCOVERY}}"
      etcd_peer_addr: "{{inventory_hostname}}:%s"
      etcd_addr: "{{inventory_hostname}}"
      etcd_data_dir: "{{VAR}}"
      etcd_name: "%m-{{NAME}}"
    ETCD_BIN: /usr/local/bin/etcd
  tasks:
  - include: tasks/compfuzor.includes type=srv
