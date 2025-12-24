---
- hosts: all
  vars:
    REPO: https://github.com/nickgnd/tmux-mcp
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
