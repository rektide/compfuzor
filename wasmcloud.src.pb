---
- hosts: all
  vars:
    TYPE: wasmcloud
    INSTANCE: git
    REPO: https://github.com/wasmCloud/wasmCloud
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
  tasks:
    - import_tasks: tasks/compfuzor.includes
