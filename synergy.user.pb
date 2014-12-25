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
    - synergy.json
    VAR_FILES:
    - name: synergy.conf.j2
      raw: True
    BINS:
    - name: build-etc
      run: True
      global: False
    LINKS:
      "~/.synergy.conf": "{{ETC}}/synergy.conf"
  tasks:
  - include: tasks/compfuzor.includes type=opt
