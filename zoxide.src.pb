---
- hosts: all
  vars:
    TYPE: zoxide
    INSTANCE: git
    REPO: https://github.com/ajeetdsouza/zoxide
  tasks:
    - import_tasks: tasks/compfuzor.includes
