---
- hosts: all
  sudo: True
  gather_facts: False
  tags:
  - packages
  - root
  vars_files:
  - vars/common.vars
  sudo: True
  tasks:
  - apt: pkg=postgresql,rabbitmq-server,memcached state=$APT_INSTALL
    only_if: not ${APT_BYPASS}
