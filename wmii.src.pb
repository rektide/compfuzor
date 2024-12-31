---
- hosts: all
  vars:
    TYPE: wmii
    INSTANCE: git
    REPO: https://github.com/0intro/wmii
    BINS:
      - name: build.sh
        exec: |
          make
      - name: install.sh
        exec: |
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
