---
- hosts: all
  gather_facts: False
  tasks:
  - include: tasks/multifuzor/clearvars.tasks
  - set_fact:
      TYPE: openstack-keystone
      PKGSETS:
      - OPENSTACK_KEYSTONE
      - OPENSTACK_KEYSTONE_NOVA
      - OPENSTACK_KEYSTONE_CLIENT
  - include: tasks/compfuzor.includes type=srv
