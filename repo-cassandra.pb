---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: cassandra
    APT_REPO: http://www.apache.org/dist/cassandra/debian
    APT_DISTRIBUTION: 20x
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks
  - include: tasks/apt.list.install.tasks
  #- include: tasks/apt.srclist.install.tasks
