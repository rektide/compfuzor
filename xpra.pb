---
- hosts: all
  gather_facts: False
  vars:
    TYPE: xpra
    INSTANCE: main
    APT_REPO: http://www.xpra.org/beta/
    APT_DISTRIBUTION: jessie
    APT_TRUST: False
    PKGS:
    - xpra
  tasks:
  - include: tasks/compfuzor.includes
