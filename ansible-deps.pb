---
- hosts: all
  user: root
  vars_files:
  - vars/ansible.vars
  - vars/apt.vars
  tasks:
  - name: apt-get install ansible dependencies
    apt: pkg=$DEPS state=$APT_INSTALL
