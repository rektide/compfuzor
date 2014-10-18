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
    - src: False
      dest: ../build
      run: True
    LINKS_BYPASS: True
    LINKS:
      "bin/build": "build"
  tasks:
  - include: tasks/compfuzor.includes
  - include: tasks/compfuzor/bins_run.tasks
  - include: tasks/compfuzor/links.tasks
