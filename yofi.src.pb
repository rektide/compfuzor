---
- hosts: all
  vars:
    TYPE: yofi
    INSTANCE: git
    REPO: https://github.com/l4l/yofi
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          cargo run --release
  tasks:
    - import_tasks: tasks/compfuzor.includes
