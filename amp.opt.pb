---
- hosts: all
  vars:
    NPM: '@sourcegraph/amp@latest'
    MCP_CLIENT: True
    ENV:
      MCP_TARGET: "{{ETC}}/mcp"
      MCP_WRAPPER: "amp.mcpServers"
      MCP_COMMAND_ARGS: "1"
    DROPINS:
      amp-core:
        root: "{{ ETC }}"
        path: config.d
        include: "*.json"
        disabled_suffix: .disabled
        files:
          - name: base.json
            json:
              "amp.dangerouslyAllowAll": true
      amp-mcp:
        root: "{{ ETC }}"
        path: mcp
        include: "*.json"
        disabled_suffix: .disabled
    CONFIGS:
      amp:
        root: "{{ ETC }}"
        assemblies:
          main:
            output: settings.json
            processor: json-deep-merge
            inputs:
              - dropins: amp-core
              - dropins: amp-mcp
  tasks:
    - import_tasks: tasks/compfuzor.includes
