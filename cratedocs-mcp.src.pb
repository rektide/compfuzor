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
    ENV: True
    BINS:
      - name: build.sh
        run: True
        content: |
          cargo build --release
      - name: install-user.sh
        content: |
          cargo install --path .
      - name: install.sh
        content: |
          ln -sfv "$(pwd)/target/release/cratedocs" $GLOBAL_BINS_DIR
      - name: install-opencode.sh
        basedir: False
        content: |
          ln -sv $DIR/etc/opencode-cratedocs-mcp.json etc/mcp/cratedocs-mcp.json
  tasks:
    - import_tasks: tasks/compfuzor.includes
