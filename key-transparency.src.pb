---
- hosts: all
  vars:
    TYPE: key-transparency
    REPO: https://github.com/google/key-transparency
    BINS:
    - name: build.sh
      exec: go get /...
  tasks:
  - include: tasks/compfuzor.includes type=src
