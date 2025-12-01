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
    BINS:
      - name: build.sh
        content: |
          go build -o bd ./cmd/bd

          cd integrations/beads-mcp
          uv sync
      - name: install.sh
        basedir: False
        content: |
          ln -sv "$DIR/bd" "$DIR/bins/beads-mcp" "$GLOBAL_BINS_DIR/"
      - name: beads-mcp
        global: True
        content: |
          uv run --project "$DIR/integrations/beads-mcp" beads-mcp
    ENV:
      BEADS_USE_DAEMON: "1"
  tasks:
    - import_tasks: tasks/compfuzor.includes
