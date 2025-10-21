---
- hosts: all
  vars:
    TYPE: codex
    INSTANCE: git
    REPO: https://github.com/openai/codex
    BINS:
      - name: install.sh
        content: |
          npm install -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
