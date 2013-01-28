---
- hosts: all
  user: rektide
  vars:
    TYPE: openstack-build
    INSTANCE: git
  vars_files:
  - "vars/common.vars"
  tasks:
  - include: tasks/opts.vars.tasks
  - git: repo=git://anonscm.debian.org/git/openstack/openstack-auto-builder.git dest=${DIR.stdout}
