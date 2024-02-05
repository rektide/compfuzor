---
- hosts: all
  vars:
    TYPE: niri
    INSTANCE: git
    REPO: https://github.com/YaLTeR/niri
    BINS:
      - name: build.sh
        exec: echo hello world
  tasks:
    - include: tasks/compfuzor.includes type=src
