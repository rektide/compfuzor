---
- hosts: all
  vars:
    REPO: https://github.com/bigcodegen/mcp-neovim-server
    TOOL_VERSIONS:
      nodejs: True
      pnpm: True
    ETC_FILES:
      - name: opencode-mcp-neovim-server.json.envsubst
        json:
          mcp:
            neovim:
              enabled: true
              type: "local"
              command: ["mcp-neovim-server"]
              environment:
                ALLOW_SHELL_COMMANDS: "${ALLOW_SHELL_COMMANDS}"
                NVIM_SOCKET_PATH: "${NVIM_SOCKET_PATH}"
    BINS:
      - name: install.sh
        content: |
          pnpm i
          pnpm link

          cat etc/opencode-mcp-neovim-server.json.envsubst | envsubst > etc/opencode-mcp-neovim-server.json
      - name: install-opencode.sh
        basedir: False
        env: False
        content: |
          # use nvim-auto-listen server or run nvim with --listen ${NVIM_LISTEN_ADDRESS} to open socket
          ln -sv {{DIR}}/etc/opencode-mcp-neovim-server.json etc/mcp/opencode-mcp-neovim-server.json
          [ -e 'bin/config.sh' ] && ./bin/config.sh
    ENV:
      ALLOW_SHELL_COMMANDS: "false"
      NVIM_SOCKET_PATH: ".nvim.socket"
  tasks:
    - import_tasks: tasks/compfuzor.includes


