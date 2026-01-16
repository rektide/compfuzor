---
- hosts: all
  vars:
    REPO: https://github.com/mcginleyr1/jj-mcp-server
    RUST: True
    RUST_BIN: jj-mcp-server
    MCP_COMMAND:
      - jj-mcp-server
  tasks:
    - import_tasks: tasks/compfuzor.includes
