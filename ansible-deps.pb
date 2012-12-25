---
- hosts: all
  user: root
  vars_files:
  - "vars/ansible.vars"
  tasks:
  - name: apt-get install ansible dependencies
    apt: pkg=$DEPS state=latest
