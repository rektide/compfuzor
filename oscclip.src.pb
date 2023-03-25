---
- hosts: all
  vars:
    TYPE: oscclip
    INSTANCE: git
    REPO: https://github.com/rumpelsepp/oscclip 
    PKGS:
      - python3-poetry
  tasks:
    - include: tasks/compfuzor.includes type=opt
