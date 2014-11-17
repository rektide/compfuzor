---
- hosts: all
  gather_facts: False
  vars: 
    TYPE: hamcrest
    INSTANCE: git
    REPO: https://github.com/hamcrest/JavaHamcrest
    BINS:
    - name: build.sh
      run: True
    - name: install-artifacts.sh
      run: True
    GLOBAL_BINS_BYPASS: True
    version: 1.3-redhat-1
  tasks:
  - include: tasks/compfuzor.includes type="src"
