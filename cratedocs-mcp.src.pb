---
- hosts: all
  vars:
    TYPE: cratedocs-mcp
    INSTANCE: git
    REPO: https://github.com/d6e/cratedocs-mcp
    ETC_FILES:
      - name: opencode-cratedocs-mcp.json
        content: |
          {
            "mcp": {
              "cratedocs": {
                "enabled": true,
                "type": "local",
                "command": ["cratedocs"]
              }
            }
          }
    RUST: True
    RUST_BIN: cratedocs
    BINS:
      - name: install-opencode.sh
        basedir: False
        content: |
          ln -sv $DIR/etc/opencode-cratedocs-mcp.json etc/mcp/cratedocs-mcp.json
          [ -e 'bin/config.sh' ] && ./bin/config.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
