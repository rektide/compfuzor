---
- hosts: all
  vars:
    TYPE: buf
    INSTANCE: git
    REPO_GO: https://github.com/bufbuild/buf
  tasks:
    - include: tasks/compfuzor.includes types=src
