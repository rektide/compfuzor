---
- hosts: all
  vars:
    TYPE: bemoji
    INSTANCE: git
    REPO: https://github.com/marty-oehme/bemoji
    PKGS:
      - wtype
    BINS:
      - name: install.sh
        exec: |
          cp bemoji ${GLOBAL_BINS_DIR}/
  tasks:
    - import_tasks: tasks/compfuzor.includes
