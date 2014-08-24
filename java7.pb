---
- hosts: all
  tags:
  - packages
  - repo
  - root
  gather_facts: False
  vars_files:
  - vars/java-webupd8.vars
  vars:
    NAME: java7-webupd8
    PKGS:
    - oracle-java7-installer
    - oracle-java7-set-default
  tasks:
  - shell: echo debconf shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
  - shell: echo debconf shared/accepted-oracle-license-v1-1 seen true | /usr/bin/debconf-set-selections
  - include: tasks/compfuzor.includes type=opt
