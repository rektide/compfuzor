---
- hosts: all
  vars:
    TYPE: vuio
    INSTANCE: git
    REPO: https://github.com/vuiodev/vuio
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install.sh
        exec: |
          echo hi
  tasks:
    - import_tasks: tasks/compfuzor.includes
