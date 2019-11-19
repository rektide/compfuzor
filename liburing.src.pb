---
- hosts: all
  vars:
    TYPE: liburing
    INSTANCE: git
    REPO: https://git.kernel.dk/liburing
  tasks:
  - include: tasks/compfuzor.includes type=src
