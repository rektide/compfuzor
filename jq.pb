---
- hosts: all
  gather_facts: false
  vars:
    TYPE: jq
    INSTANCE: git
    REPO: https://github.com/stedolan/jq.git
    PKGS:
    - libonig-dev
    BINS: 
    - name: make-jq
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
