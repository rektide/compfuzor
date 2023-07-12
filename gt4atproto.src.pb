---
- hosts: all
  vars:
    TYPE: gt4atproto
    INSTANCE: git
    REPO: https://github.com/feenkcom/gt4atproto
    BINS:
      - name: extract-install
        exec:
          # something to read the code snippet out of README.md
  tasks:
    - include: tasks/compfuzor.includes type=src
