---
- hosts: all
  vars:
    TYPE: libixp
    INSTANCE: git
    REPO: https://github.com/0intro/libixp
    BINS:
      - name: build.sh
        exec: |
          make
      - name: install.sh
        exec: |
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
