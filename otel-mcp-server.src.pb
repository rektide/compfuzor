---
- hosts: all
  vars:
    TYPE: otel-mcp-server
    INSTANCE: git
    REPO: https://github.com/traceloop/opentelemetry-mcp-server
    ENV:
      mcp_name: otel
      env2mcp_prefix_env: otel_mcp
      opencode_mcp_file: "${DIR}/etc/mcp/opencode-otel.json"
      otel_mcp_backend: jaeger
      otel_mcp_url: 'http://localhost:16686/'
    BINS:
      - src: ../env2mcp
        raw: True
      - name: build.sh
        content: |
          uv sync --frozen
      - name: config.sh
        content: |
          echo generating mcp from template
          $DIR/bin/env2mcp \
            --set-json mcp.${MCP_NAME}.command='["uv", "run", "--project", "{{DIR}}"]' \
            --set-json mcp.${MCP_NAME}.enabled=true \
            --set-json mcp.${MCP_NAME}.type=local \
            --set-json '$schema=https://opencode.ai/config.json' \
            > $OPENCODE_MCP_FILE
      - name: install-opencode.sh
        basedir: False
        env: False
        content: |
          # run from opencode directory
          $DIR/bin/config.sh
          echo
          echo installing
          (
            source $DIR/env;
            ln -sv $OPENCODE_MCP_FILE etc/mcp/
          )
          [ -e 'bin/config.sh' ] && ./bin/config.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
