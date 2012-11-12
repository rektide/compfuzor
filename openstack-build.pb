---
- hosts: all
  user: rektide
  vars_files:
    - "vars/main.vars"
    - "vars/openstack-build.vars"
  tasks:
    - include: "tasks/openstack-build.tasks"
