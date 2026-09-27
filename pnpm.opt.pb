---
- hosts: all
  vars:
    TYPE: pnpm
    INSTANCE: main
    # One deployment, two opt-in provisioning lanes. The render is inert:
    # build-mise.sh installs the pinned pnpm into the invoking user's mise,
    # and nothing is promoted until an operator runs a lane by hand.
    #   install-user.sh   per-user mise: promote the rendered pin to the
    #                     mise global config (`mise use --global`).
    #   install-system.sh static system binary: extract the self-contained
    #                     release into DIR/dist and link GLOBAL_BINS_DIR/pnpm
    #                     -- ambient pnpm for root, cron, services, /bin/sh,
    #                     and other users, no node/mise needed.
    version: 12.7.0
    # Shared-consumer convention (see block-in-file-git): the system lane's
    # global link resolves through DIR, so group members must traverse it.
    GROUP: users
    TOOL_VERSIONS:
      pnpm: True
    pnpm_home: "$HOME/.local/share/pnpm"
    GET_URLS:
      - url: https://github.com/pnpm/pnpm/releases/download/v{{version}}/pnpm-linux-x64.tar.gz
        dest: pnpm-linux-x64.tar.gz
        # world-readable: the fetch lands root-owned under SRCS_DIR, but
        # install-system.sh (run as the invoking user) must read it.
        mode: "0644"
    ENV_LIST:
      - version
    ETC_FILES:
      - name: config.zsh
        content: |
          [ -n "$PNPM_HOME" ] || export PNPM_HOME="$HOME/.local/share/pnpm"
    BINS:
      - name: install-user.sh
        deployment_rooted: True
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
      - name: install-system.sh
        # deployment_rooted: derive DIR from this script's own path -- a
        # caller's ambient DIR (another deployment's env) must not redirect
        # the promotion or the GLOBAL_BINS_DIR link.
        deployment_rooted: True
        content: |
          set -e
          # The tarball layout (pnpm binary + dist/node-gyp-bin +
          # dist/node_modules) mirrors PNPM_HOME's; keep the tree beside the
          # linked binary so pnpm finds its support files.
          rm -rf "${DIR}/dist"
          mkdir -p "${DIR}/dist"
          tar -xzf {{SRC}}/pnpm-linux-x64.tar.gz -C "${DIR}/dist"
          chmod 0755 "${DIR}/dist/pnpm"
          # Archive member modes are private and mkdir picks the invoking
          # user's group; open the tree for the deployment group (the
          # invoking user may not chgrp themselves).
          chgrp -R {{GROUP}} "${DIR}/dist" 2>/dev/null || sudo chgrp -R {{GROUP}} "${DIR}/dist"
          chmod -R g+rX "${DIR}/dist"
          SUDO_CMD=""
          [ -w "${GLOBAL_BINS_DIR}" ] || SUDO_CMD="sudo"
          ${SUDO_CMD} ln -sfnv "${DIR}/dist/pnpm" "${GLOBAL_BINS_DIR}/pnpm"
          "${DIR}/dist/pnpm" --version
  tasks:
    - import_tasks: tasks/compfuzor.includes
