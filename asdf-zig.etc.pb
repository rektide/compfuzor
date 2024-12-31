---
- hosts: all
  vars:
    TYPE: asdf-zig
    INSTANCE: main
    BINS:
      - name: install.sh
        exec: |
          asdf plugin-add zig https://github.com/asdf-community/asdf-zig
  tasks:
    - import_tasks: tasks/compfuzor.includes
      
