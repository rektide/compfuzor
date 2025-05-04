---
- hosts: all
  vars:
    TYPE: waydroid
    INSTANCE: git
    REPO: https://github.com/waydroid/waydroid
    BINS:
      - name: build.sh
        exec: |
          echo hi
  tasks:
    - import_tasks: tasks/compfuzor.includes
