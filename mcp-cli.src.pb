---
- hosts: all
  vars:
    REPO: https://github.com/philschmid/mcp-cli
    BUN: True
    MCP_CLIENT:
      dropins: mcp-cli-servers
      wrapper: mcpServers
      command_args: true
    DROPINS:
      mcp-cli-servers:
        root: "{{ ETC }}"
        path: mcp
        include: "*.json"
        disabled_suffix: .disabled
    CONFIGS:
      mcp-cli:
        root: "{{ ETC }}"
        assemblies:
          main:
            output: mcp_servers.json
            processor: json-deep-merge
            inputs:
              - dropins: mcp-cli-servers
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
