---
- hosts: all
  vars:
    TYPE: upnptube
    INSTANCE: git
    REPO: https://github.com/mas94uk/upnpTube
  tasks:
    - import_tasks: tasks/compfuzor.includes
