---
- hosts: all
  gather_facts: False
  vars:
    TYPE: synergy
    INSTANCE: main
    USERMODE: True
    PKGS:
    - synergy
    ETC_FILES:
    - synergy.conf
    LINKS:
      "~/.synergy.conf": "{{ETC}}/synergy.conf"
  tasks:
  - include: tasks/compfuzor.includes type=opt
