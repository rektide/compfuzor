
---
- hosts: all
  vars:
    TYPE: nanomsg
    INSTANCE: git
    REPO: https://github.com/nanomsg/nanomsg
    SRV_DIR: True
    BINS:
    - name: "make-{{NAME}}"
      src: "../make-src"
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
