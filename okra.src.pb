---
- hosts: all
  vars:
    TYPE: okra
    INSTANCE: git
    REPO: https://github.com/HSAFoundation/Okra-Interface-to-HSA-Device
    PKGS:
    - libelf-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
