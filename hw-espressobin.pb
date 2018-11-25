---
- hosts: all
  vars:
    TYPE: hw-espressobin
    INSTANCE: main
    REPO_WORKTREE:
    - src: uboot-git
      dest: uboot
    - src: linux
      dest: linux
    ETC_FILES:
    BINS:
    - name: build.sh
      exec: |
        echo try this
  tasks:
  - include: tasks/compfuzor.includes type=src
