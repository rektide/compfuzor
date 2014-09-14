
---
- hosts: all
  vars:
    TYPE: nanomsg
    INSTANCE: git
    REPO: https://github.com/nanomsg/nanomsg
    PKGS:
    - libev-dev
    - libev-libevent-dev
    BINS:
    - name: "make-{{NAME}}"
      src: "../make-src"
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
