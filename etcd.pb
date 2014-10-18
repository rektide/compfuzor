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
    SRCS_TOO: True

    BIN_DIRS: True
    BINS:
    - dest: ../build
      run: True
      bypassGlobal: True
    - global: etcd
    GLOBAL_BINS_BYPASS: True
    LINKS_BYPASS: True
    LINKS:
      "bin/build": "build"
  tasks:
  - include: tasks/compfuzor.includes
  - include: tasks/compfuzor/bins.tasks GLOBAL_BINS_BYPASS=False # install into global
  - include: tasks/compfuzor/links.tasks # link in build
  - file: path={{DIR}} mode=771 # allow others to use etcd
