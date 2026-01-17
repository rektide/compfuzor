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
    ENV:
      MCP_TARGET: "{{ETC}}/mcp"
      MCP_WRAPPER: "amp.mcpServers"
      MCP_COMMAND_ARGS: "1"
    BINS:
      - name: config.sh
        content: |
          shopt -s nullglob
          configs=(${DIR}/etc/mcp/*.json)

          if [ ${{ '{#' }}configs[@]} -eq 0 ]; then
            echo "no mcp configs found" >&2
            exit 0
          fi

          jq -s 'reduce .[] as $item ({}; . * $item)' ${DIR}/etc/base.json "${configs[@]}" > ${DIR}/etc/settings.json
      - name: install.sh
        content: |
          mkdir -p ~/.config/amp
          ln -sfv ${DIR}/etc/settings.json ~/.config/amp/settings.json
      - name: install-mcp.sh
        src: ../install-mcp.sh
        basedir: False
      - name: install-mcp.ts
        src: ../install-mcp.ts
        basedir: False
  tasks:
    - import_tasks: tasks/compfuzor.includes
