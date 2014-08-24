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
    NAME: java8-webupd8
    PKGS:
    - oracle-java8-installer
    - oracle-java8-set-default
    - maven
  tasks:
  - shell: echo debconf shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
  - shell: echo debconf shared/accepted-oracle-license-v1-1 seen true | /usr/bin/debconf-set-selections
  - include: tasks/compfuzor.includes
