---
- hosts: all
  vars:
    TYPE: context7
    INSTANCE: git
    REPO: https://github.com/upstash/context7
    BINS:
      - name: install.sh
        content: |
          npm install -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
