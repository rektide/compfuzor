---
- hosts: all
  vars:
    TYPE: fractalbits
    INSTANCE: git
    REPO: https://github.com/fractalbits-labs/fractalbits-main
    BINS:
      - name: build.sh
        content: |
          cargo build --release
  tasks:
    - import_tasks: tasks/compfuzor.includes
