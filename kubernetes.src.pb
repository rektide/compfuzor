---
- hosts: all
  gather_facts: False
  vars:
    TYPE: kubernetes
    INSTANCE: git
    REPO: https://github.com/GoogleCloudPlatform/kubernetes
    BINS:
    - exec: make all
      pwd: repo
    PKGS:
    - rsync
  tasks:
  - include: tasks/compfuzor.includes
