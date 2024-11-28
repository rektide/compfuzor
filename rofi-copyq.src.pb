---
- hosts: all
  vars:
    TYPE: rofi-copyq
    INSTANCE: git
    REPO: https://github.com/cjbassi/rofi-copyq
    ENV:
      womp: womp
    BINS:
      - name: install.sh
        exec: |
          cp rofi-copyq $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
