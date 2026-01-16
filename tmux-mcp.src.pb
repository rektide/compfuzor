---
- hosts: all
  vars:
    REPO: https://github.com/nickgnd/tmux-mcp
    NODEJS: True
    MCP_COMMAND:
      - tmux-mcp
    BINS:
      - name: install.sh
        content: |
          [ -e $HOME/.local/bin/tmux-mcp ] && rm $HOME/.local/bin/tmux-mcp
          chmod +X $(pwd)/build/index.js
          ln -sf $(pwd)/build/index.js $GLOBAL_BINS_DIR/tmux-mcp
  tasks:
    - import_tasks: tasks/compfuzor.includes
