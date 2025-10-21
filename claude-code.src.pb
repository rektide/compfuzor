---
- hosts: all
  vars:
    TYPE: claude-code
    INSTANCE: git
    REPO: https://github.com/anthropics/claude-code
    BINS:
      - name: install.sh
        content: |
          npm install -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
