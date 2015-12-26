---
- hosts: all
  vars:
    TYPE: usergrid
    INSTANCE: git
    REPO: https://github.com/apache/usergrid
    BINS:
    - exec: "(cd stack; mvn clean install)"
 
  tasks:
  - include: tasks/compfuzor.includes type=src
