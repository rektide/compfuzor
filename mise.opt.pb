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
          if [ "${#_vars[@]}" -eq 0 ]; then
            echo "mise-systemd-env: mise reported no environment variables" >&2
            exit 0
          fi
          systemctl --user set-environment "${_vars[@]}"
          echo "mise-systemd-env: pushed ${#_vars[@]} variable(s)$([ "$INCLUDE_PATH" -eq 1 ] && echo " (incl PATH)")"
  tasks:
    - import_tasks: tasks/compfuzor.includes
