---
- hosts: all
  vars:
    TYPE: rustup
    INSTANCE: main
    GET_URLS:
      - url: https://sh.rustup.rs
        dest: rustup.sh
    BINS:
      - name: build.sh
        basedir: src
        exec: |
          sh rustup.sh -y
  tasks:
    - include: tasks/compfuzor.includes type=opt
