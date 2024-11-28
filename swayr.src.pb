---
- hosts: all
  vars:
    TYPE: swayr
    INSTANCE: git
    REPO: https://git.sr.ht/~tsdh/swayr
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
  tasks:
    - import_tasks: tasks/compfuzor.includes
