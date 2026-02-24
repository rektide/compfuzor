---
- hosts: all
  vars:
    REPO: https://github.com/rektide/tmux-tracker
  tasks:
    - import_tasks: tasks/compfuzor.includes
