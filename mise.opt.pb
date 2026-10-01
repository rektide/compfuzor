---
- hosts: all
  vars:
    TYPE: mise
    INSTANCE: main
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
    bash_rc: "$HOME/.bashrc"
    bash_profile: "$HOME/.bash_profile"
    # Literal (not ${VAR:-default}): this lands in the systemd EnvironmentFile
    # via ENV_LIST, and systemd does no shell expansion -- deferred syntax
    # reaches mise as a literal string and panics its settings parser.
    mise_npm_package_manager: "pnpm"
    # (sysenv disabled 2026-09-05; only consumed by the mise-user-env ExecStart.)
    #mise_user_env_path: False
    ENV_LIST:
      - bash_rc
      - bash_profile
      - mise_npm_package_manager
    # Cache areas inventoried by bin/mise-cache.sh (status/list/gc/clear).
    # Fields: name (gc/clear selection key), desc, paths (list; space-joined
    # into the rendered catalog; runtime-expanded, so $HOME and
    # ${XDG_CACHE_HOME:-...} forms work; entries must not contain spaces),
    # query (ask the tool itself for its
    # root), fallback (used when the query tool is off PATH), gc (safe
    # reclaim command), clear (native command, `rm`, or `none` for
    # visibility-only areas), expand (status reports one-level child sizes).
    # Cache/data roots follow mise's own env overrides (MISE_CACHE_DIR,
    # MISE_DATA_DIR) so a redirected mise sees its redirected caches.
    mise_cache_areas:
      - name: mise-cache
        desc: mise internal metadata cache
        query: mise cache path
        fallback: "${MISE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mise}"
        gc: mise cache prune
        clear: mise cache clear
      - name: mise-downloads
        desc: mise install download staging
        paths: ["${MISE_DATA_DIR:-$HOME/.local/share/mise}/downloads"]
        clear: rm
      - name: mise-installs
        desc: mise-managed tool installs
        paths: ["${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs"]
        gc: mise prune --tools
        clear: none
        expand: true
      - name: rustup
        desc: rustup toolchains outside mise (visibility only)
        paths: ["${RUSTUP_HOME:-$HOME/.rustup}"]
        clear: none
        expand: true
      - name: cargo
        desc: cargo registry and git caches
        paths: ["${CARGO_HOME:-$HOME/.cargo}/registry", "${CARGO_HOME:-$HOME/.cargo}/git"]
        clear: rm
      - name: npm
        desc: npm download cache
        query: npm config get cache
        fallback: "$HOME/.npm"
        clear: npm cache clean --force
      - name: pnpm
        desc: pnpm content-addressed store and metadata cache
        query: pnpm store path
        fallback: "${XDG_DATA_HOME:-$HOME/.local/share}/pnpm/store"
        paths: ["${XDG_CACHE_HOME:-$HOME/.cache}/pnpm"]
        gc: pnpm store prune
        clear: rm
      - name: yarn
        desc: yarn classic and berry caches
        paths: ["${XDG_CACHE_HOME:-$HOME/.cache}/yarn", "$HOME/.yarn/berry/cache"]
        clear: rm
      - name: bun
        desc: bun install cache
        paths: ["${BUN_INSTALL:-$HOME/.bun}/install/cache"]
        clear: bun pm cache rm
      - name: deno
        desc: deno remote module cache
        paths: ["${DENO_DIR:-$HOME/.cache/deno}"]
        clear: deno clean
      - name: go-mod
        desc: go module source cache
        query: go env GOMODCACHE
        fallback: "${GOPATH:-$HOME/go}/pkg/mod"
        clear: go clean -modcache
      - name: go-build
        desc: go build cache
        query: go env GOCACHE
        fallback: "${XDG_CACHE_HOME:-$HOME/.cache}/go-build"
        clear: go clean -cache
      - name: gradle
        desc: gradle dependency caches
        paths: ["${GRADLE_USER_HOME:-$HOME/.gradle}/caches"]
        clear: rm
      - name: maven
        desc: maven local repository
        paths: ["$HOME/.m2/repository"]
        clear: rm
      - name: pip
        desc: pip download and build cache
        paths: ["${XDG_CACHE_HOME:-$HOME/.cache}/pip"]
        clear: pip cache purge
      - name: uv
        desc: uv python and package cache
        paths: ["${XDG_CACHE_HOME:-$HOME/.cache}/uv"]
        gc: uv cache prune
        clear: uv cache clean
      - name: nuget
        desc: dotnet nuget packages
        paths: ["$HOME/.nuget/packages"]
        clear: dotnet nuget locals all --clear
      - name: prettier
        desc: prettier cache
        paths: ["${XDG_CACHE_HOME:-$HOME/.cache}/prettier"]
        clear: rm
    STATUSES:
      - status-mise-bash.sh
      # --fast: sizes come from du, which can take minutes across ~100G of
      # caches; the aggregate status.sh skips du, direct runs measure.
      - name: mise-cache.ts
        args: [status, --fast]
    BINS:
      - name: install-user.sh
        content: |
          # Remove activation blocks owned by older mise.opt.pb revisions.
          for startup in "${ZDOTDIR:-$HOME}/.zshenv" "${ZDOTDIR:-$HOME}/.zshrc"; do
            [ ! -f "$startup" ] || sed -i '/^# {{NAME}} start$/,/^# {{NAME}} end$/d' "$startup"
          done
          if command -v mise >/dev/null 2>&1
          then
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
      # Retire the bash precursor; mise-cache.ts replaces it.
      - name: mise-cache.sh
        state: absent
      # Cache inventory + selective gc/clear for mise and the tools it
      # installs; shared template, rendered from mise_cache_areas above.
      # TypeScript (node:util parse-args CLI) via the Node bin template.
      - name: mise-cache.ts
        src: ../mise-cache.ts
        runtime: node
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
