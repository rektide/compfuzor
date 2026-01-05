---
- hosts: all
  vars:
    REPO: https://github.com/AvengeMedia/DankMaterialShell
    BINS:
      - name: build.sh
        content: |
          make
      - name: install.sh
        content: |
          sudo make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
