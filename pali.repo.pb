---
- hosts: all
  become: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: pali
    APT_REPO: http://ppa.launchpad.net/pali/pali/ubuntu
    APT_DISTRIBUTION: oneiric
  tasks:
  - import_tasks: tasks/compfuzor/apt.tasks
