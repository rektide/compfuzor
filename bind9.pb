---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars_files:
  - vars/common.vars
  tasks:
  - apt: state=${APT_INSTALL} pkg=bind9,bind9-doc,bind9utils
