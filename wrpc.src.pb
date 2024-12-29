---
- hosts: all
  vars:
    TYPE: wrpc
    INSTANCE: git
    REPO: https://github.com/bytecodealliance/wrpc
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
  tasks:
    - import_tasks: tasks/compfuzor.includes
