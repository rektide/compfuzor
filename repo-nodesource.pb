---
- hosts: all
  tags:
  - packages
  - root
  vars:
    TYPE: nodesource
    INSTANCE: 8.x
    NAME: "{{TYPE}}-{{INSTANCE}}"
    APT_REPO: "https://deb.nodesource.com/node_{{INSTANCE}}"
    APT_SOURCELIST: "{{TYPE}}"
  tasks:
  - include: tasks/compfuzor/apt.tasks
