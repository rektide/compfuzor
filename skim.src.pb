---
- hosts: all
  vars:
    TYPE: skim
    INSTANCE: git
    REPO: https://github.com/skim-rs/skim
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          (cd skim; cargo build --release)
          (cd xtask; cargo build --release)
  tasks:
    - import_tasks: tasks/compfuzor.includes

