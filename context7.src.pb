---
- hosts: all
  vars:
    TYPE: context7
    INSTANCE: git
    REPO: https://github.com/upstash/context7
    MCP_URL: "https://mcp.context7.com/mcp"
    MCP_HEADERS:
      CONTEXT7_API_KEY: "${CONTEXT7_API_KEY}"
    BINS:
      - name: install.sh
        content: |
          npm install -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
