---
- hosts: all
  vars:
    TYPE: dbus-action
    INSTANCE: git
    REPO: https://github.com/bulletmark/dbus-action
    BINS:
      - name: build.sh
        exec: |
          make
      - name: install.sh
        sudo: True
        exec: |
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
