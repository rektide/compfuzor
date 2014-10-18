---
- hosts: all
  gather_facts: False
  vars:
    NAME: pkgs-eda
    PKGSET: EDA
    DIR_BYPASS: True
  tasks:
  - include: tasks/compfuzor.includes
