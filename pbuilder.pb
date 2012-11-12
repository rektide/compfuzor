---
- hosts: all
  sudo: True
  vars_files:
    - "vars/pbuilder.vars"
  tasks:
    - include: "tasks/pbuilder.tasks"
