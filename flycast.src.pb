---
- hosts: all
  vars:
    TYPE: flycast
    INSTANCE: git
    REPO: https://github.com/flyinghead/flycast
    BINS:
      - name: build.sh
        content: |
          mkdir build
          cd build
          cmake .. -GNinja
          ninja
  tasks:
    - import_tasks: tasks/compfuzor.includes
