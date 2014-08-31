---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: ceph
    APT_REPO: http://ceph.com/debian-firefly/
    APT_DISTRIBUTION: wheezy
  tasks:
  - include: tasks/compfuzor/apt.tasks
