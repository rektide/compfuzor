---
- hosts: all
  gather_facts: False
  vars:
    NAME: docker
    INSTANCE: main
    PKGSET: DOCKER
  tasks:
  - include: tasks/compfuzor.includes
