---
- hosts: all
  gather_facts: False
  tags:
  - go
  - build
  vars:
    TYPE: etcd
    INSTANCE: git
    REPO: https://github.com/coreos/etcd
    PKGSETS:
    - GO
    BINS:
    - exec: ./build
    - global: etcd
    - global: etcdctl
    GLOBAL_BINS_BYPASS: True
  tasks:
  - include: tasks/compfuzor.includes type=src
  - include: tasks/compfuzor/bins_link_global.tasks
