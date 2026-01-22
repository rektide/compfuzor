---
- hosts: all
  vars:
    NPM_PACKAGE: '@sourcegraph/amp@latest'
    ETC_DIRS:
      - mcp
    ETC_FILES:
      - name: base.json
        json:
          "amp.dangerouslyAllowAll": true
    MCP_CLIENT: True
    ENV:
      MCP_TARGET: "{{ETC}}/mcp"
      MCP_WRAPPER: "amp.mcpServers"
      MCP_COMMAND_ARGS: "1"
      MCP_CONF: settings.json
  tasks:
    - import_tasks: tasks/compfuzor.includes
