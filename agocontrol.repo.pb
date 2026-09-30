---
- hosts: all
  become: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: agocontrol
    APT_REPO: http://mirror.at.agocontrol.com/debian
    APT_DISTRIBUTION: unstable
  tasks:
  - import_tasks: tasks/compfuzor/apt.tasks
