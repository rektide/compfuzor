---
- hosts: all
  vars:
    TYPE: mopidy
    INSTANCE: jessie
    APT_REPO: http://apt.mopidy.com/
  tasks:
  - include: tasks/compfuzor.includes type=pkg
