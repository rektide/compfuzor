---
- hosts: all
  vars:
    REPO: https://github.com/rektide/tmux-tracker
    RUST: True
    SYSTEMD_INSTALL: false
    SYSTEMD_SERVICES:
      ExecStart: tmux-tracker
  tasks:
    - import_tasks: tasks/compfuzor.includes
