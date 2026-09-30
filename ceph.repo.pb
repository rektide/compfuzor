---
- hosts: all
  become: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: ceph
    APT_REPO: http://ceph.com/debian-firefly/
    APT_DISTRIBUTION: wheezy
  tasks:
  - import_tasks: tasks/compfuzor/apt.tasks
