---
- hosts: all
  vars:
    TYPE: mise
    INSTANCE: main
    SYSTEMD_SERVICE: mise-user-env
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_UNITS:
      Before: default.target
    SYSTEMD_SERVICES:
      Type: oneshot
      WorkingDirectory: "%h"
      ExecStart: "{{DIR}}/bin/mise-systemd-env.sh{{ ' --path' if mise_user_env_path|default(False)|bool else '' }}"
    SYSTEMD_INSTALLS:
      WantedBy: default.target
    # NOTE: the shell-rc activation blocks below (mise.zshrc/mise.zprofile/
    # mise.bashrc/mise.bash_profile) DUPLICATE a shell-framework's own mise
    # loader. The `zim-mise` zimfw module (joke/zim-mise) already runs
    # `mise activate zsh` + hook-env + completions during zim init on Linux,
    # so on zim-using boxes injecting these into ~/.zshenv/~/.zprofile means
    # mise is activated 3x (zshenv, zprofile, zim-mise). install-user.sh should
    # detect an active zim/zim-mise loader and skip the block-in-file adds in
    # that case (see TODO in install-user.sh). Bash has no equivalent framework
    # loader, so the bash blocks are still wanted there.
    ETC_FILES:
      - name: mise.zshrc
        content: |
          eval "$(mise activate zsh)"
      - name: mise.zprofile
        content: |
          eval "$(mise activate zsh --shims)"
      - name: mise.bashrc
        content: |
          eval "$(mise activate bash)"
      - name: mise.bash_profile
        content: |
          eval "$(mise activate bash --shims)"
    zsh_rc: "${ZDOTDIR:-$HOME}/.zshrc"
    zsh_profile: "${ZDOTDIR:-$HOME}/.zprofile"
    bash_rc: "$HOME/.bashrc"
    bash_profile: "$HOME/.bash_profile"
    mise_npm_package_manager: "${MISE_NPM_PACKAGE_MANAGER:-pnpm}"
    mise_user_env_path: False
    ENV_LIST:
      - zsh_rc
      - zsh_profile
      - bash_rc
      - bash_profile
      - mise_npm_package_manager
    BINS:
      - name: install-user.sh
        content: |
          # NOTE: the block-in-file adds below inject `mise activate zsh` into
          # ~/.zshrc and ~/.zprofile. On zim-using boxes the `zim-mise` zimfw
          # module already activates mise during zim init, so these adds are
          # redundant there (triple activation: zshenv, zprofile, zim-mise).
          # TODO(install-user): detect an active zim/zim-mise loader and skip
          # the zsh_rc/zsh_profile injection when present. Detection options:
          #   * grep `zmodule .*zim-mise` in ${ZIM_CONFIG_FILE:-/opt/zim-main/etc/zimfw.conf}
          #   * test -f ~/.cache/zim/modules/zim-mise/mise-activate.zsh
          #     (generated when zim-mise's Linux branch has run)
          #   * check fpath for the `_mise` completion in an interactive zsh
          # Also honor an explicit MISE_SKIP_ZSH_RC=1 override. Bash has no
          # equivalent framework loader, so install-bash.user.sh is unaffected.
          block-in-file \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i {{DIR}}/etc/mise.zshrc \
            -o "${ZSH_RC:-{{zsh_rc}}}"
          block-in-file \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i {{DIR}}/etc/mise.zprofile \
            -o "${ZSH_PROFILE:-{{zsh_profile}}}"
          if command -v mise >/dev/null 2>&1
          then
            mise settings set npm.package_manager "${MISE_NPM_PACKAGE_MANAGER:-{{mise_npm_package_manager}}}"
          fi
      - name: install-bash.user.sh
        content: |
          block-in-file \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i {{DIR}}/etc/mise.bashrc \
            -o "${BASH_RC:-{{bash_rc}}}"
          block-in-file \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i {{DIR}}/etc/mise.bash_profile \
            -o "${BASH_PROFILE:-{{bash_profile}}}"
      - name: mise-systemd-env.sh
        basedir: False
        content: |
          if ! command -v mise >/dev/null 2>&1; then
            echo "mise-systemd-env: mise is not on PATH" >&2
            exit 1
          fi
          if ! command -v jq >/dev/null 2>&1; then
            echo "mise-systemd-env: jq is required but not on PATH" >&2
            exit 1
          fi
          INCLUDE_PATH=0
          if [ "${1:-}" = "--path" ]; then
            INCLUDE_PATH=1
            shift
          fi
          if [ "$INCLUDE_PATH" -eq 1 ]; then
            _filter='to_entries[] | "\(.key)=\(.value)"'
          else
            _filter='to_entries[] | select(.key != "PATH") | "\(.key)=\(.value)"'
          fi
          mapfile -t _vars < <(cd "$HOME" && mise env -J | jq -r "$_filter")
          if [ "{{ '${#' }}_vars[@]}" -eq 0 ]; then
            echo "mise-systemd-env: mise reported no environment variables" >&2
            exit 0
          fi
          systemctl --user set-environment "{{ '${' }}_vars[@]}"
          echo "mise-systemd-env: pushed {{ '${#' }}_vars[@]} variable(s)$([ "$INCLUDE_PATH" -eq 1 ] && echo " (incl PATH)")"
  tasks:
    - import_tasks: tasks/compfuzor.includes
