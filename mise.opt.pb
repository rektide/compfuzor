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
    # NOTE: zsh coverage is two-tier, matching mise's own recommendation:
    #   * ~/.zshenv gets `mise activate zsh --shims`. zshenv is sourced by
    #     EVERY zsh -- interactive or not (`zsh -c`, ssh commands, compfuzor
    #     bins run via BINS_SHELL=/bin/zsh in bins_run.tasks) -- so mise-managed
    #     tools resolve in non-interactive contexts. `--shims` skips the prompt
    #     hooks, making it safe outside interactive shells.
    #   * ~/.zshrc keeps plain `mise activate zsh` for interactive hook-env
    #     updates. install-user.sh SKIPS this add on zim boxes (zim-mise module
    #     detection, see there); shims in zshenv + a later interactive activate
    #     is mise's documented combo.
    # The old ~/.zprofile `--shims` block was dropped: login shells source
    # zshenv first, so it added nothing beyond the zshenv shims.
    # Bash has no framework loader, so the bash blocks are still wanted.
    ETC_FILES:
      - name: mise.zshenv
        content: |
          eval "$(mise activate zsh --shims)"
      - name: mise.zshrc
        content: |
          eval "$(mise activate zsh)"
      - name: mise.bashrc
        content: |
          eval "$(mise activate bash)"
      - name: mise.bash_profile
        content: |
          eval "$(mise activate bash --shims)"
    zsh_env: "${ZDOTDIR:-$HOME}/.zshenv"
    zsh_rc: "${ZDOTDIR:-$HOME}/.zshrc"
    bash_rc: "$HOME/.bashrc"
    bash_profile: "$HOME/.bash_profile"
    mise_npm_package_manager: "${MISE_NPM_PACKAGE_MANAGER:-pnpm}"
    mise_user_env_path: False
    ENV_LIST:
      - zsh_env
      - zsh_rc
      - bash_rc
      - bash_profile
      - mise_npm_package_manager
    BINS:
      - name: install-user.sh
        content: |
          # The zshenv add below is unconditional: it is the non-interactive
          # floor (`zsh -c`, ssh commands, ansible BINS via BINS_SHELL) and
          # shim-based, so no prompt hooks are involved.
          # The zshrc add only enables interactive hook-env. On zim-using
          # boxes the `zim-mise` module (enabled at core phase in zim.opt.pb)
          # already runs cached `mise activate zsh` + hook-env + completions
          # during zim init, so the zshrc add is skipped there. Detection:
          #   1. MISE_SKIP_ZSH_RC=1 -- explicit override
          #   2. a `zmodule ... zim-mise` line in the assembled zimfw config
          #      (ZIM_CONFIG_FILE, default the ~/.config/zsh/zimfw.conf link)
          #   3. zim-mise's cached activation marker under ZIM_HOME (proof the
          #      module has actually run)
          # Bash has no equivalent framework loader, so install-bash-user.sh
          # is unaffected.
          block-in-file \
            -n ${NAME:-{{NAME}}} \
            -C true \
            -i {{DIR}}/etc/mise.zshenv \
            -o "${ZSH_ENV:-{{zsh_env}}}"

          _skip_zshrc=0
          if [ "${MISE_SKIP_ZSH_RC:-}" = "1" ]; then
            _skip_zshrc=1
          else
            _conf="${ZIM_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimfw.conf}"
            if [ -f "$_conf" ] && grep -Eq '^[[:space:]]*zmodule .*zim-mise' "$_conf"; then
              _skip_zshrc=1
            elif [ -f "${ZIM_HOME:-$HOME/.cache/zim}/modules/zim-mise/mise-activate.zsh" ]; then
              _skip_zshrc=1
            fi
          fi
          if [ "$_skip_zshrc" = "1" ]; then
            echo "mise: skipping zshrc activate (zim-mise detected or MISE_SKIP_ZSH_RC=1)"
          else
            block-in-file \
              -n ${NAME:-{{NAME}}} \
              -C true \
              -i {{DIR}}/etc/mise.zshrc \
              -o "${ZSH_RC:-{{zsh_rc}}}"
          fi
          if command -v mise >/dev/null 2>&1
          then
            mise settings set npm.package_manager "${MISE_NPM_PACKAGE_MANAGER:-{{mise_npm_package_manager}}}"
          fi
      - name: install-bash-user.sh
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
