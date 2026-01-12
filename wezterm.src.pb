---
- hosts: all
  vars:
    REPO: https://github.com/wezterm/wezterm
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
