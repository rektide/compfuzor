---
- hosts: all
  sudo: True
  gather_facts: False
  vars_files:
  - vars/common.vars
  tasks:
  - apt: state=${APT_INSTALL} pkg=screen
    only_if: not ${APT_BYPASS}
