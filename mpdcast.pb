---
- hosts: all
  vars:
    TYPE: mpdcast
    INSTANCE: git
    REPO: https://github.com/rektide/mpdcast
    BINS:
    - name: build.sh
      exec: cd repo && npm link .
      become: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
