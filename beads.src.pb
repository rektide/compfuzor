---
- hosts: all
  vars:
    TYPE: beads
    INSTANCE: git
    REPO: https://github.com/steveyegge/beads.git
    TOOL_VERSIONS:
      go: True
    ETC_FILES:
      - name: opencode-beads-mcp.json
        content: |
          {
            "mcp": {
              "beads": {
                "enabled": true,
                "type": "local",
                "command": ["beads-mcp"],
                "environment": {
                  "BEADS_USE_DAEMON": "{env:BEADS_USE_DAEMON}"
                }
              }
            }
          }
    ENV: True
    BINS:
      - name: build.sh
        content: |
          go build -o bd ./cmd/bd

          cd integrations/beads-mcp
          uv sync --frozen
      - name: install.sh
        basedir: False
        content: |
          ln -sv "$DIR/bd" "$DIR/bins/beads-mcp" "$GLOBAL_BINS_DIR/"
      - name: install-opencode.sh
        basedir: False
        content: |
          ln -sv $DIR/etc/opencode-beads-mcp.json etc/mcp/
          [ -e 'bin/config.sh' ] && ./bin/config.sh
      - name: beads-mcp
        global: True
        content: |
          exec uv run --frozen --project "$DIR/integrations/beads-mcp" beads-mcp
    ENV:
      BEADS_USE_DAEMON: "1"
  tasks:
    - import_tasks: tasks/compfuzor.includes
