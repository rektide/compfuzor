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
    NAME: java9-webupd8
    PKGS:
    - oracle-java9-installer
    - oracle-java9-set-default
    - maven
  tasks:
  - shell: echo debconf shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
  - shell: echo debconf shared/accepted-oracle-license-v1-1 seen true | /usr/bin/debconf-set-selections
  - include: tasks/compfuzor.includes
