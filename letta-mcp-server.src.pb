---
- hosts: all
  vars:
    TYPE: letta-mcp-server
    INSTANCE: git
    REPO: https://github.com/oculairmedia/Letta-MCP-server
    ENV:
      LETTA_BASE_URL:
      LETTA_PASSWORD:
      LOG_LEVEL: info
    BINS:
      - name: install.sh
        content: |
          pnpm install
      - name: run-.sh
          pnpm run 
      - name: install-opencode.sh
        content: |
          echo hello
  tasks:
    - import_tasks: tasks/compfuzor.includes

