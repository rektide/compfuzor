---
- hosts: all
  vars:
    TYPE: pnpm
    INSTANCE: main
    TOOL_VERSIONS:
      pnpm: 10
    ETC_FILES:
      - name: config.zsh
        content: |
          [ -n "$PNPM_HOME" ] || export PNPM_HOME="$HOME/.local/bin"
    BINS:
      - name: install-user.sh
        content: |
          mkdir -p $PNPM_HOME
          block-in-file -n '{{TYPE}}' -i etc/.tool-versions $HOME/.tool-versions -C
          block-in-file -n '{{TYPE}}' -i etc/config.zsh $HOME/.zshrc
          if command -v mise
          then
            (cd $HOME; mise install)
          fi
    ENV:
      - PNPM_HOME
    pnpm_home: "$HOME/.local/bin"
  tasks:
    - import_tasks: tasks/compfuzor.includes
