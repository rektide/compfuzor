---
- hosts: all
  vars:
    TYPE: opencode
    INSTANCE: git
    REPO: https://github.com/sst/opencode
    ETC_FILES:
      - name: tool-versions
        content: |
          bun 1
          go 1
      - name: opencode.json
        content: |
          {
            "$schema": "https://opencode.ai/config.json",
            "mcp": {
              "context7": {
                "enabled": true,
                "type": "remote",
                "url": "https://context7.liam.sh/mcp",
                "headers": {
                  "Authorization": "Bearer {{CONTEXT7_API_KEY}}"
                } 
              }
            }
          }
    BINS:
      - name: install.sh
        content: |
          [ ! -f '.tool-versions' ] && ln -s etc/tool-versions .tool-versions
          bun install --frozen-lockfile
          mkdir -p ~/.local/share/opencode/log
      # TODO: compfuzor helpers for installing content, automate this below
      - name: install-user.sh
        basedir: False
        content: |
          [ -n "$TARGET" ] || TARGET="$HOME/.config/opencode"
          mkdir -p $TARGET
          ln -s ${DIR}/etc/opencode.json $TARGET/
      - name: opencode
        basedir: False
        global: True
        content: |
          exec bun run --cwd $DIR dev $(pwd)
    ENV:
      CONTEXT7_API_KEY: example-key
  tasks:
    - import_tasks: tasks/compfuzor.includes
