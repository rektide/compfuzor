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
  - include: tasks/compfuzor/bins_run.tasks
  - include: tasks/compfuzor/bins.tasks GLOBAL_BINS_BYPASS=False
  - include: tasks/compfuzor/links.tasks
