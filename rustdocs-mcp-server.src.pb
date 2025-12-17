---
- hosts: all
  vars:
    TYPE: rustdocs-mcp-server
    INSTANCE: git
    REPO: https://github.com/Govcraft/rust-docs-mcp-server
    TOOL_VERSIONS:
      rust: True
    ENV:
      CRATES_FILE: etc/crates.txt
      OPENCODE_TEMPLATE_FILE: etc/opencode-rustdocs-mcp.json.template
    ETC_FILES:
      - name: crates.txt
        content: |
          pipewire
          fuser
      - name: opencode-rustdocs-mcp.json.template
        content: |
          {
            "mcp": {
              "rustdocs-${CRATE}": {
                "enabled": true,
                "type": "local",
                "command": ["rustdocs_mcp_server", "${CRATE}"]
              }
            }
          }
    BINS:
      - name: build.sh
        # slow
        #run: True
        content: |
          cargo build --release
      - name: build-cache.sh
        content: |
          # no way to cache only, fails after building
          set +e

          while IFS= read -r line
          do
            [ -z "$line" ] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue

            # Parse crate name (first column) and optional features (second column)
            crate=$(echo "$line" | awk '{print $1}')
            features=$(echo "$line" | awk '{$1=""; print $0}' | xargs)

            ./target/release/rustdocs_mcp_server $crate ${feature:+$feature} </dev/null
            echo
          done < "$CRATES_FILE"
      # create opencode configs with this
      - name: config.sh
      - name: install-user.sh
        content: |
          cargo install --path .
      - name: install.sh
        content: |
          ln -sfv "$(pwd)/target/release/cratedocs" $GLOBAL_BINS_DIR
      - name: install-opencode.sh
        basedir: False
        content: |
          ln -sv $DIR/etc/opencode*json etc/mcp/
          [ -e 'bin/config.sh' ] && ./bin/config.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
