---
- hosts: all
  vars:
    REPO: https://github.com/github/github-mcp-server
    GO: True
    GO_BIN: github-mcp-server
    GO_TARGET: ./cmd/github-mcp-server
    MCP_COMMAND:
      - github-mcp-server
      - stdio
    MCP_ENV:
      - GITHUB_PERSONAL_ACCESS_TOKEN
      - GITHUB_TOOLSETS
  tasks:
    - import_tasks: tasks/compfuzor.includes
