---
- hosts: all
  vars:
    TYPE: mcp-neovim-server
    INSTANCE: git
    REPO: https://github.com/bigcodegen/mcp-neovim-server
    TOOL_VERSIONS:
      nodejs: True
      pnpm: True
    ETC_FILES:
      - name: opencode-mcp-neovim-server.json
        content: |
          {
            "mcp": {
              "mcp-neovim-server": {
                "enabled": true,
                "type": "local",
                "command": ["mcp-neovim-server"],
                "environment": {
                  "ALLOW_SHELL_COMMANDS": "{env:ALLOW_SHELL_COMMANDS}",
                  "NVIM_SOCKET": "{env:NVIM_LISTEN_ADDRESS}"
                }
              }
            }
          }
    BINS:
      - name: install.sh
        content: |
          pnpm i
          pnpm link
      - name: install-opencode.sh
        basedir: False
        content: |
          # mcp server in opencode also will need the env vars provided here
          # and run nvim with --listen ${NVIM_LISTEN_ADDRESS} to open socket
          ln -sv $DIR/etc/opencode-mcp-neovim-server.json etc/mcp/mcp-neovim-server.json
          [ -e 'bin/config.sh' ] && ./bin/config.sh
    ENV:
      ALLOW_SHELL_COMMANDS: "false"
      NVIM_LISTEN_ADDRESS: "${XDG_RUNTIME_DIR}/nvim.socket"
  tasks:
    - import_tasks: tasks/compfuzor.includes


