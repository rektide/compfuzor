---
- hosts: all
  vars:
    TYPE: afk-dim
    INSTANCE: git
    REPO: https://github.com/rektide/afk-dim
    RUST: True
    PKGS:
      - libwayland-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
