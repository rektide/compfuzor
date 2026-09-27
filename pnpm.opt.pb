---
- hosts: all
  vars:
    TYPE: pnpm
    INSTANCE: main
    # User-scope mise pnpm. TOOL_VERSIONS renders the pin from PNPM_VERSION
    # (vars/common.yaml; 12 as of 2026-09), build-mise.sh installs it into
    # the invoking user's mise, and install-user.sh (run per-user, manually)
    # promotes the pin to the mise global config. Per-user by design: root
    # and other users get nothing -- for an ambient system pnpm see
    # pnpm-sys.opt.pb (static release binary in GLOBAL_BINS_DIR).
    TOOL_VERSIONS:
      pnpm: True
    pnpm_home: "$HOME/.local/bin"
    ETC_FILES:
      - name: config.zsh
        content: |
          [ -n "$PNPM_HOME" ] || export PNPM_HOME="$HOME/.local/bin"
    BINS:
      - name: install-user.sh
        content: |
          set -e
          mkdir -p "${PNPM_HOME:-{{pnpm_home}}}"
          command="${CONFIG_BLOCK_IN_FILE:-block-in-file}"
          "$command" -n ${NAME:-{{NAME}}} -i {{DIR}}/etc/config.zsh "$HOME/.zshrc"

          if command -v mise >/dev/null 2>&1
          then
            mise install
            pnpm_version=$(awk '$1 == "pnpm" {print $2}' {{DIR}}/.tool-versions)
            if [ -n "$pnpm_version" ]
            then
              mise use --global pnpm@${pnpm_version}
            fi
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
