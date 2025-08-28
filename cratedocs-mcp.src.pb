---
- hosts: all
  vars:
    TYPE: cratedocs-mcp
    INSTANCE: git
    REPO: https://github.com/d6e/cratedocs-mcp
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install-user.sh
          cargo install --path .
  tasks:
    - import_tasks: tasks/compfuzor.includes
