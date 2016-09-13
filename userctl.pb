---
- hosts: all
  vars:
    TYPE: userctl
    INSTANCE: git
    REPO: https://github.com/rektide/userctl
    BINS:
    - name: build.sh
      exec: cd repo && npm link .
      become: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
