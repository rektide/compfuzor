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
    LINKS_BYPASS: True
    LINKS:
    - foo
    BIN_DIRS: True
    BINS:
    - src: False
      dest: ../build
      run: true
  tasks:
  - include: tasks/compfuzor.includes
  - include: tasks/compfuzor/bins_run.tasks
  #- include: tasks/compfuzor/links.tasks
