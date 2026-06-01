---
- hosts: all
  vars:
    TYPE: code-minimap
    INSTANCE: src
    REPO: https://github.com/wfxr/code-minimap
  tasks:
    - import_tasks: tasks/compfuzor.includes
