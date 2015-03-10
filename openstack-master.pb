---
- hosts: all
  gather_facts: False
  tasks:
  - set_facts:
      INSTANCE: main
  - include: tasks/multifuzor/persist.tasks
  - include: openstack-keystone.pb
