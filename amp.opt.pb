---
- hosts: all
  vars:
    NPM: '@sourcegraph/amp@latest'
    MCP_CLIENT:
      remote: mcp
      wrapper: amp.mcpServers
      command_args: true
    ETC_DIRS:
      - config.d
      - mcp
    ETC_FILES:
      - name: config.d/base.json
        json:
          "amp.dangerouslyAllowAll": true
    CONFIGS:
      settings.json:
        name: amp
        processor: json-deep-merge
        inputs:
          - glob: config.d/*.json
            name: amp-core
          - glob: mcp/*.json
            name: mcp
            remote: true
  tasks:
    - import_tasks: tasks/compfuzor.includes
