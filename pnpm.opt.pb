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
          block-in-file -n '{{TYPE}}' -i etc/config.zsh $HOME/.zshrc

          if command -v mise
          then
            mise install
            pnpm_version=$(grep pnpm .tool-versions|awk '{print $2}')
            mise use --global pnpm@${pnpm_version}
          fi
    ENV:
      - PNPM_HOME
    pnpm_home: "$HOME/.local/bin"
  tasks:
    - import_tasks: tasks/compfuzor.includes
