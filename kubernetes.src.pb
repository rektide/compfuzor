---
- hosts: all
  gather_facts: False
  vars:
    NAME: kubernetes
    INSTANCE: git
    REPO: https://github.com/GoogleCloudPlatform/kubernetes
  tasks:
  - include: tasks/compfuzor.includes
