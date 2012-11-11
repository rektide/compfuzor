---
- hosts: all
  user: rektide
  vars_files:
    - "vars/ansible.vars"
  tasks:
    - include: "tasks/xdg.vars.tasks"
    - include: "tasks/ansible.tasks"
