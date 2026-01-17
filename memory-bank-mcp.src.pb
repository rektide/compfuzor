---
- hosts: all
  vars:
    TYPE: memory-bank-mcp
    INSTANCE: git
    REPO: https://github.com/alioshr/memory-bank-mcp/
    NODEJS: True
    MCP_COMMAND:
      - memory-bank-mcp
    BINS:
      - name: install.sh
        content: |
          pnpm i
          pnpm link -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
