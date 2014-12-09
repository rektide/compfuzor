---
- hosts: all
  gather_facts: False
  vars:
    NAME: docker
    INSTANCE: main
    PKGSET: DOCKER
  tasks:
  - include: tasks/systemd.isactive.test unit=docker.service
  - include: tasks/compfuzor.includes
