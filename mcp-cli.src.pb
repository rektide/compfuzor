---
- hosts: all
  vars:
    REPO: https://github.com/philschmid/mcp-cli
    BUN: True
    ETC_DIRS:
      - mcp
      - mcp-portable
    CONFIGS:
      mcp_servers.json:
        name: mcp-cli
        processor: json-deep-merge
        inputs:
          # Pre-wrapped fragments keep {"mcpServers": {...}} shape.
          - glob: mcp/*.json
            name: mcp
            remote: true
          # Portable producer records (etc/mcp.json). mcp-cli's own schema
          # wants `command` as a string with separate `args` and names the
          # environment map `env` (src/config.ts: StdioServerConfig), so the
          # placement splits the record's command array and renames the key.
          # No envsubst: mcp-cli substitutes ${VAR} itself at runtime
          # (strict by default; MCP_STRICT_ENV=false downgrades to a warning),
          # so secrets stay out of the assembled file.
          - glob: mcp-portable/*.json
            name: mcp-portable
            remote: true
            place:
              at: mcpServers
              as: object
              command_args: true
              rename:
                environment: env
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
          ln -sfn $(pwd)/etc/mcp_servers.json ~/.config/mcp/mcp_servers.json
  tasks:
    - import_tasks: tasks/compfuzor.includes
