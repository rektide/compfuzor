---
- hosts: all
  vars:
    REPO: https://github.com/bigcodegen/mcp-neovim-server
    TOOL_VERSIONS:
      nodejs: True
      pnpm: True
    MCP_COMMAND:
      - mcp-neovim-server
    MCP_ENV:
      ALLOW_SHELL_COMMANDS: "${ALLOW_SHELL_COMMANDS}"
      NVIM_SOCKET_PATH: "${NVIM_SOCKET_PATH}"
    BINS:
      - name: install.sh
        content: |
          pnpm i
          pnpm link
    ENV:
      ALLOW_SHELL_COMMANDS: "false"
      NVIM_SOCKET_PATH: ".nvim.socket"
  tasks:
    - import_tasks: tasks/compfuzor.includes
