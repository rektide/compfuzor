---
- hosts: all
  vars:
    TYPE: couchdb
    INSTANCE: main
    PKGS:
    - apache-couchdb
  tasks:
  - include: tasks/compfuzor.includes type=srv
