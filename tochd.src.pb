---
- hosts: all
  vars:
    TYPE: tochd
    INSTANCE: git
    REPO: https://github.com/thingsiplay/tochd
    PKGS:
      - mame-tools
      - 7zip
  tasks:
    - import_tasks: tasks/compfuzor.includes
