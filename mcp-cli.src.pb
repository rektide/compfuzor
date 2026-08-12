---
- hosts: all
  vars:
    REPO: https://github.com/philschmid/mcp-cli
    BUN: True
    MCP_CLIENT:
      remote: mcp
      wrapper: mcpServers
      command_args: true
    ETC_DIRS:
      - mcp
    CONFIGS:
      mcp_servers.json:
        name: mcp-cli
        processor: json-deep-merge
        inputs:
          - glob: mcp/*.json
            name: mcp
            remote: true
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
          ln -s $(pwd)/etc/mcp_servers.json ~/.config/mcp/mcp_servers.json
  tasks:
    - import_tasks: tasks/compfuzor.includes
