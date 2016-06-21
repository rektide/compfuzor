---
- hosts: all
  vars:
    TYPE: ca
    INSTANCE: main
    ETC_FILES:
    - signing.cnf
    - root.cnf
    VAR_DIRS:
    - certs
    - crl
    - newcerts
    - private
    VAR_FILES:
    - index.txt
    - serial
  tasks:
  - include: tasks/compfuzor.includes type=srv
