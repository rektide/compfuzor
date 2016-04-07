---
- hosts: all
  gather_facts: False
  vars:
    NAME: kubernetes
    INSTANCE: git
    REPO: https://github.com/GoogleCloudPlatform/kubernetes
    BINS:
    - run: make all
    PKGS:
    - rsync
  tasks:
  - include: tasks/compfuzor.includes
