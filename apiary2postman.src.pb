---
- hosts: all
  vars:
    TYPE: apiary2postman
    INSTANCE: git
    REPO: https://github.com/thecopy/apiary2postman
    BINS:
    - name: apiary2postman.py
      basedir: apiary2postman
      global: True
      src: False
  tasks:
  - include: tasks/compfuzor.includes type=src
