---
- hosts: all
  tags:
  - packages
  - root
  vars:
    NAME: timescaledb
    APT_REPO: http://ppa.launchpad.net/timescale/timescaledb-ppa/ubuntu
    APT_DISTRIBUTION: bionic
  tasks:
  - include: tasks/compfuzor/apt.tasks
