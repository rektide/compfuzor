---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: pali
    APT_REPO: http://ppa.launchpad.net/pali/pali/ubuntu
    APT_DISTRIBUTION: oneiric
  tasks:
  - include: tasks/compfuzor/apt.tasks
