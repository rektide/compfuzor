---
- hosts: all
  vars:
    REPO: https://github.com/gregorias/coop.nvim
  tasks:
    - import_tasks: tasks/compfuzor.includes
