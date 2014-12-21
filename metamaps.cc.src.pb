---
- hosts: all
  gather_facts: False
  vars:
    TYPE: metamaps
    INSTANCE: git
    REPO: https://github.com/metamaps/metamaps_gen002.git
    PKGS:
    - nodejs
    - libpq-dev
    # NEEDS:
    #- redis
    #- postgres
  tasks:
  - include: tasks/compfuzor.includes
