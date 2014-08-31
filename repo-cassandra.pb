---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: cassandra
    APT_REPO: http://www.apache.org/dist/cassandra/debian
    APT_DISTRIBUTION: 21x
  tasks:
  - include: tasks/compfuzor/apt.tasks
