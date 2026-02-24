---
- hosts: all
  vars:
    REPO: https://github.com/rektide/tmux-tracker
    RUST: True
    SYSTEMD_SERVICES:
      Exec: tmux-tracker
  tasks:
    - import_tasks: tasks/compfuzor.includes
