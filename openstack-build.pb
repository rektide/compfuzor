---
- hosts: all
  user: rektide
  vars_files:
  - "vars/common.vars"
  - "vars/openstack-build.vars"
  vars:
    OPT_
  tasks:
  - include: tasks/common.tasks
  - include: tasks/openstack-build.tasks
