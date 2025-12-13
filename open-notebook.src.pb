---
- hosts: all
  vars:
    TYPE: open-notebook
    INSTANCE: git
    REPO: https://github.com/lfnovo/open-notebook
    BINS:
      - name: build.sh
        content: |
          #make
  tasks:
    - import_tasks: tasks/compfuzor.includes
