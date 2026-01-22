---
- hosts: all
  vars:
    REPO: https://github.com/philschmid/mcp-cli
    BUN: True
    MCP_CLIENT: True
    ENV:
      MCP_COMMAND_ARGS: "1"
      MCP_CONF: mcp_servers.json
      MCP_WRAPPER: mcpServers
    BINS:
      - name: build.sh
        content: |
          bun run build
      - link: ../dist/mcp-cli
        phase: postRun
        global: True
      - name: install-user.sh
        content: |
          mkdir -p ~/.config/mcp
          ln -s $(pwd)/etc/${MCP_CONF} ~/.config/mcp/mcp_servers.json
  tasks:
    - import_tasks: tasks/compfuzor.includes
