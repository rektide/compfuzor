---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: agocontrol
    APT_REPO: http://mirror.at.agocontrol.com/debian
    APT_DISTRIBUTION: unstable
  tasks:
  - include: tasks/compfuzor/apt.tasks
