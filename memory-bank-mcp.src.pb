---
- hosts: all
  vars:
    TYPE: memory-bank-mcp
    INSTANCE: git
    REPO: https://github.com/alioshr/memory-bank-mcp/
    BINS:
      - name: install.sh
        content: |
          pnpm link
  tasks:
    - import_tasks: tasks/compfuzor.includes
