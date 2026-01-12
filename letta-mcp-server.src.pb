---
- hosts: all
  vars:
    TYPE: letta-mcp-server
    INSTANCE: git
    REPO: https://github.com/oculairmedia/Letta-MCP-server
    MCP_COMMAND:
      - pnpm
      - run
    ENV:
      LETTA_BASE_URL:
      LETTA_PASSWORD:
      LOG_LEVEL: info
    BINS:
      - name: install.sh
        content: |
          pnpm install
  tasks:
    - import_tasks: tasks/compfuzor.includes

