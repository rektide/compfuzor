---
- hosts: all
  vars:
    TYPE: ghostty
    INSTANCE: git
    REPO: https://github.com//ghostty-org/ghostty
    BINS:
      - name: build.sh
        exec: echo hi
      - name: install.sh
        exec: echo bar
  tasks:
    - import_tasks: tasks/compfuzor.includes
