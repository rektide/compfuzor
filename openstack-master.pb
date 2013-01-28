---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  vars_files:
  - vars/common.vars
  sudo: True
  tasks:
  - apt: pkg=postgresql,rabbitmq-server,memcached state=$APT_INSTALL
    unless: ${APT_BYPASS}
