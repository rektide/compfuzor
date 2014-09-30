---
- hosts: all
  gather_facts: False
  vars:
    TYPE: openzwave
    INSTANCE: git
    TGZ: http://openzwave.com/downloads/openzwave-1.0.791.tar.gz
  tasks:
  - include: tasks/compfuzor.includes
