---
- hosts: all
  vars:
    TYPE: miraclecast
    INSTANCE: git
    REPO: https://github.com/albfan/miraclecast
    GIT_ACCEPT: True
    MAKE_AUTOCONF: True
    PKGS:
    - libreadline-dev
  tasks:
  - include: tasks/compfuzor.includes type=src 
