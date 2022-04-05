---
- hosts: all
  vars:
    TYPE: zx
    INSTANCE: git
    REPO: https://github.com/google/zx
    BINS:
    - name: install.sh
      exec: |
        npm install
        npm link
  tasks:
  - include: tasks/compfuzor.includes type=src
