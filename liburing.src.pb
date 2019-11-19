---
- hosts: all
  vars:
    TYPE: liburing
    INSTANCE: git
    REPO: https://git.kernel.dk/liburing
    OPT_DIR: True
    BINS:
    - name: build.sh
      content: |
        ./configure --prefix="{{OPT}}"
    - name: install.sh
      content: |
        # echo lol wut
  tasks:
  - include: tasks/compfuzor.includes type=src
