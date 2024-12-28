---
- hosts: all
  vars:
    TYPE: libglee
    INSTANCE: git
    REPO: https://github.com/kallisti5/glee
    BINS:
      - name: build.sh
        exec: |
          mkdir -p build
          cd build
          cmake ..
          make
      - name: install.sh
        exec: |
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
