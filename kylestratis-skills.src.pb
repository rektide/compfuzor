---
- hosts: all
  vars:
    REPO: https://github.com/kylestratis/kyle-claude-plugins
  tasks:
    - import_tasks: tasks/compfuzor.includes
