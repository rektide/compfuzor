---
- hosts: all
  vars:
    TYPE: git-auto-commit
    INSTANCE: git
    REPO: https://github.com/jauntywunderkind/git-auto-commit
    BINS:
      - name: build.sh
        exec: |
          npm install
          npm link
      - src: "../git-auto-commit.js"
        name: "git-auto-commit"
        global: True
        exists: False
  tasks:
    - include: tasks/compfuzor.includes type=src
