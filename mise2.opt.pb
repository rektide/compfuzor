---
- hosts: all
  vars:
    TYPE: mise2
    INSTANCE: main
    RUNTIME_FLOW_EXECUTION: true
    # sysenv disabled 2026-09-05: the mise->systemd user environment bridge
    # (mise-user-env oneshot pushing `mise env` via systemctl --user
    # set-environment) was an ambient env channel competing with the zim
    # module env (zim.opt.pb channels). Shells and services get their env
    # from their own declared deployments again. Re-enable by uncommenting
    # and re-running install-user + `systemctl --user enable --now`.
    #SYSTEMD_SERVICE: mise-user-env
    #SYSTEMD_SCOPE: user
    #SYSTEMD_INSTALL: user
    #SYSTEMD_UNITS:
    #  Before: default.target
    #SYSTEMD_SERVICES:
    #  Type: oneshot
    #  WorkingDirectory: "%h"
    #  ExecStart: "{{DIR}}/bin/mise-systemd-env.sh{{ ' --path' if mise_user_env_path|default(False)|bool else '' }}"
    #SYSTEMD_INSTALLS:
    #  WantedBy: default.target
    # Zsh activation is owned by zim.opt.pb's zimenv channel. rektide/zim-mise
    # loads exactly once from ~/.zshenv: full activation for interactive shells,
    # shims only for non-interactive shells. Bash has no framework loader, so
    # its independent activation blocks remain here.
    ETC_FILES:
      - name: mise.bashrc
        content: |
          eval "$(mise activate bash)"
      - name: mise.bash_profile
        content: |
          eval "$(mise activate bash --shims)"
    bash_rc: "$HOME/.config/mise2/bashrc"
    bash_profile: "$HOME/.config/mise2/bash_profile"
    mise2_zdotdir: "$HOME/.config/mise2/zdot"
    mise2_config_dir: "$HOME/.config/mise2/config"
    # Literal (not ${VAR:-default}): this lands in the systemd EnvironmentFile
    # via ENV_LIST, and systemd does no shell expansion -- deferred syntax
    # reaches mise as a literal string and panics its settings parser.
    mise_npm_package_manager: "pnpm"
    # (sysenv disabled 2026-09-05; only consumed by the mise-user-env ExecStart.)
    #mise_user_env_path: False
    ENV_LIST:
      - bash_rc
      - bash_profile
      - mise2_zdotdir
      - mise2_config_dir
      - mise_npm_package_manager
    STATUSES:
      - status-mise-bash.sh
    BINS:
      - name: install-user.sh
        content: |
          # Remove activation blocks owned by older mise.opt.pb revisions.
          for startup in "${MISE2_ZDOTDIR:-{{mise2_zdotdir}}}/.zshenv" "${MISE2_ZDOTDIR:-{{mise2_zdotdir}}}/.zshrc"; do
            [ ! -f "$startup" ] || sed -i '/^# {{NAME}} start$/,/^# {{NAME}} end$/d' "$startup"
          done
          if command -v mise >/dev/null 2>&1
          then
            MISE_CONFIG_DIR="${MISE2_CONFIG_DIR:-{{mise2_config_dir}}}" \
              mise settings set npm.package_manager "${MISE_NPM_PACKAGE_MANAGER:-{{mise_npm_package_manager}}}"
          fi
      - name: install-bash-user.sh
        content: |
          command=${CONFIG_BLOCK_IN_FILE:-block-in-file}
          "$command" \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i "{{DIR}}/etc/mise.bashrc" \
            -o "${BASH_RC:-{{bash_rc}}}"
          "$command" \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i "{{DIR}}/etc/mise.bash_profile" \
            -o "${BASH_PROFILE:-{{bash_profile}}}"
      - name: block-status.sh
        src: ../block-status.sh
        basedir: False
        compose: False
      - name: status-mise-bash.sh
        basedir: False
        content: |
          status=0
          "{{DIR}}/bin/block-status.sh" "${NAME:-{{NAME}}}" "{{DIR}}/etc/mise.bashrc" "${BASH_RC:-{{bash_rc}}}" || status=1
          "{{DIR}}/bin/block-status.sh" "${NAME:-{{NAME}}}" "{{DIR}}/etc/mise.bash_profile" "${BASH_PROFILE:-{{bash_profile}}}" || status=1
          exit "$status"
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
