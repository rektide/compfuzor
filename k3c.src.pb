---
- hosts: all
  vars:
    TYPE: k3c
    INSTANCE: git
    REPO: https://github.com/rancher/k3c
    OPTS_DIRS: True
  tasks:
  - include: tasks/compfuzor.includes type=src
