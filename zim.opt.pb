---
- hosts: all
  vars:
    TYPE: zim
    INSTANCE: main
    ZIM_HOST: true
    zim_home: "$HOME/.cache/zim"
    zim_env_home: "$HOME/.cache/zim-env"
    zim_env_config: "{{ ETC }}/zimenv"
    zim_config_link: "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimfw.conf"
    CONFIGS:
      zimrc:
        processor: block-in-file
        validate: 'zsh -dfn "$CONFIG_CANDIDATE"'
        inputs:
          - glob: zimrc.d/*.conf
            name: zimrc
            remote: true
        block:
          remove_match:
            - '^zim-main-zimfw-'
            - '^zim/main/'
      zimenv:
        processor: block-in-file
        validate: 'zsh -dfn "$CONFIG_CANDIDATE"'
        inputs:
          - glob: zimenv.d/*.conf
            name: zimenv
            remote: true
        block:
          remove_match:
            - '^zim-main-zimfw-'
            - '^zim/main/'
    ENV:
      ZIM_CONFIG_FILE: "{{ ETC }}/zimrc"
    ENV_LIST:
      - zim_home
      - zim_env_home
      - zim_env_config
      - zim_config_link
      - ZIM_CONFIG_FILE
    GET_URLS:
      - https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
    PKGS:
      - bat
      - eza
      - fzf
      - zoxide
    # Zim module declaration. gen_zim renders one fragment per module under
    # etc/zim/<channel>/{active,disabled}/; install-zim.sh delegates them to
    # config-remote.ts and config.sh assembles zimrc and zimenv in sorted
    # filename order. `phase` is a name (core/prompt/tools/
    # completion/late) or a number 00-99 for fine placement between bands.
    ZIM_MODULES:
      - source: https://github.com/rektide/zim-mise
        channel: zimenv
        phase: core
        comment: Single early mise load; full interactively, shims otherwise. Mode/args via zstyle ':zim:plugins:mise' (see module README).

      # --- core (20) ---
      - source: environment
        phase: core
        comment: Sets sane Zsh built-in environment options.
      - source: input
        phase: core
        comment: Applies correct bindkeys for input events.
      - source: utility
        phase: core
        comment: Utility aliases and functions. Adds colour to ls, grep and less.
      # --- prompt (40) ---
      - source: duration-info
        phase: prompt
        comment: Exposes to prompts how long the last command took to execute.
      - source: git-info
        phase: prompt
        comment: Exposes git repository status information to prompts.
      - source: prompt-pwd
        phase: prompt
      - source: minimal
        phase: prompt
        comment: A heavily reduced, ASCII-only version of the Spaceship and Starship prompts.
      - source: asciiship
        phase: prompt
        enabled: false
      - source: https://gitlab.com/Spriithy/basher.git
        phase: prompt
        enabled: false
      - source: spaceship-prompt/spaceship-prompt
        phase: prompt
        args: --name spaceship --no-submodules
        enabled: false
      - source: sindresorhus/pure
        phase: prompt
        args: --source async.zsh --source pure.zsh
        enabled: false
      - source: https://github.com/joke/zim-oh-my-posh
        phase: prompt
        enabled: false
      - source: https://github.com/joke/zim-starship
        phase: prompt
        enabled: false
      - source: sorin
        phase: prompt
        enabled: false
      - source: agnoster
        phase: prompt
        enabled: false
      - source: eriner
        phase: prompt
        enabled: false
      - source: https://codeberg.org/iff/pay-respects
        phase: prompt
        enabled: false
      - source: magic-enter
        phase: prompt
        enabled: false

      # --- tools (55) ---
      - source: exa
        phase: tools
      - source: fzf
        phase: tools
      - source: git
        phase: tools
      - source: k
        phase: tools
      - source: termtitle
        phase: tools
      - source: rektide/zim-zoxide
        phase: tools
        comment: cached init + completions, no cd override
      - source: https://github.com/joke/zim-github-cli
        phase: tools
      - source: https://github.com/joke/zim-helm
        phase: tools
      - source: https://github.com/joke/zim-kubectl
        phase: tools
      - source: https://github.com/lipov3cz3k/zsh-uv
        phase: tools
      - source: https://github.com/shihanng/zim-atuin
        phase: tools
      - source: rektide/zim-atuin-session
        phase: tools
      - source: rektide/zim-beads
        phase: tools
      - source: rektide/zim-claude
        phase: tools
      - source: rektide/zim-jaeger
        phase: tools
      - source: rektide/zim-jujutsu
        phase: tools
      - source: rektide/zim-mosh
        phase: tools
      - source: rektide/zim-niri
        phase: tools
      - source: rektide/zim-opencode
        phase: tools
      - source: rektide/zim-timoni
        phase: tools
      - source: rektide/zim-tgo
        phase: tools
      - source: rektide/zim-systemd-envvar
        phase: tools
      # disabled tool alternatives, preserved for inspection / recovery
      - source: https://github.com/hmgle/aider-zsh-complete
        phase: tools
        enabled: false
      - source: https://github.com/jnooree/zoxide-zsh-completion
        phase: tools
        enabled: false
        comment: replaced by rektide/zim-zoxide
      - source: kiesman99/zim-zoxide
        phase: tools
        enabled: false
        description: kiesman99
        comment: renamed -> vietz-dev
      - source: vietz-dev/zim-zoxide
        phase: tools
        enabled: false
        description: vietz-dev
      - source: antoineco/zim-zoxide
        phase: tools
        enabled: false
        description: antoineco
      - source: https://github.com/joke/zim-chezmoi
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-gopass
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-istioctl
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-kn
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-k9s
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-skaffold
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-steampipe
        phase: tools
        enabled: false
      - source: https://github.com/joke/zim-yq
        phase: tools
        enabled: false
      - source: https://github.com/MichaelAquilina/zsh-you-should-use
        phase: tools
        enabled: false
      - source: https://github.com/pressdarling/codex-zsh-plugin
        phase: tools
        enabled: false
      - source: https://github.com/shanwker1223/zim-alias-finder
        phase: tools
        enabled: false
        comment: "also needs: zstyle ':zim:plugins:alias-finder' autoload yes"
      - source: https://github.com/shihanng/zim-kustomize
        phase: tools
        enabled: false
      - source: https://raw.githubusercontent.com/sheax0r/etcdctl-zsh/refs/heads/master/_etcdctl
        phase: tools
        enabled: false

      # --- completion (70) ---
      - source: zsh-users/zsh-completions
        phase: completion
        args: --fpath src
        comment: Additional completion definitions for Zsh.
      - source: completion
        phase: completion
        comment: Enables smart tab completion; must be sourced after all modules that add completion definitions.

      # --- late (85) ---
      - source: zsh-users/zsh-syntax-highlighting
        phase: late
        comment: Fish-like syntax highlighting; must be sourced after completion.
      - source: zsh-users/zsh-autosuggestions
        phase: late
        comment: Fish-like autosuggestions. Set ZSH_AUTOSUGGEST_MANUAL_REBIND=1 for performance.
      - source: https://github.com/lukechilds/zsh-better-npm-completion
        phase: late
      - source: zsh-users/zsh-history-substring-search
        phase: late
        enabled: false
        comment: must be sourced after zsh-syntax-highlighting
    BINS:
      - name: zimfw-channel.sh
        basedir: False
        content: |
          channel=${1:?usage: zimfw-channel.sh CHANNEL [ACTION [OPTION]]}
          shift
          case "$channel" in
            zimrc)
              home="${ZIM_HOME:-{{zim_home}}}"
              config="${ZIM_CONFIG_FILE:-{{ETC}}/zimrc}"
              ;;
            zimenv)
              home="${ZIM_ENV_HOME:-{{zim_env_home}}}"
              config="${ZIM_ENV_CONFIG:-{{zim_env_config}}}"
              ;;
            *)
              echo "unknown Zim channel: $channel" >&2
              exit 2
              ;;
          esac
          [ "$#" -gt 0 ] || set -- install
          exec zsh -dfc '
            ZIM_HOME=$1
            ZIM_CONFIG_FILE=$2
            controller=$3
            shift 3
            source "$controller" "$@"
          ' "zimfw-$channel" "$home" "$config" "{{DIR}}/src/zimfw.zsh" "$@"
      - name: install-user.sh
        basedir: False
        content: |
          echo promoting zim fragments
          {{DIR}}/bin/install-zim.sh {{DIR}}
          {{DIR}}/bin/config.sh
          # Remove the old single-loader block before installing channel blocks.
          for startup in "${ZDOTDIR:-$HOME}/.zshenv" "${ZDOTDIR:-$HOME}/.zshrc"; do
            [ ! -f "$startup" ] || sed -i '/^# {{NAME}} start$/,/^# {{NAME}} end$/d' "$startup"
          done
          echo installing zimenv in zshenv
          block-in-file -n {{NAME}}-zimenv -i {{DIR}}/etc/zimenv.zsh -o ${ZDOTDIR:-$HOME}/.zshenv
          echo installing zimrc in zshrc
          block-in-file -n {{NAME}}-zimrc -i {{DIR}}/etc/zimrc.zsh -o ${ZDOTDIR:-$HOME}/.zshrc
          echo symlinking zimrc
          mkdir -p "$(dirname "${ZIM_CONFIG_LINK:-{{zim_config_link}}}")"
          ln -sfv "${ZIM_CONFIG_FILE}" "${ZIM_CONFIG_LINK:-{{zim_config_link}}}"
      - name: status.sh
        basedir: False
        content: |
          status=0
          config_link="${ZIM_CONFIG_LINK:-{{zim_config_link}}}"
          zshenv="${ZDOTDIR:-$HOME}/.zshenv"
          zshrc="${ZDOTDIR:-$HOME}/.zshrc"
          zimenv_config="${ZIM_ENV_CONFIG:-{{zim_env_config}}}"
          zimenv_home="${ZIM_ENV_HOME:-{{zim_env_home}}}"

          if [ ! -f "$ZIM_CONFIG_FILE" ]; then
            echo "drift: generated zimrc is missing: $ZIM_CONFIG_FILE"
            status=1
          elif [ ! "${ZIM_HOME:-{{zim_home}}}/init.zsh" -nt "$ZIM_CONFIG_FILE" ]; then
            echo "drift: zimrc init is missing or stale: ${ZIM_HOME:-{{zim_home}}}/init.zsh"
            status=1
          fi
          if [ ! -f "$zimenv_config" ]; then
            echo "drift: generated zimenv is missing: $zimenv_config"
            status=1
          elif [ ! "$zimenv_home/init.zsh" -nt "$zimenv_config" ]; then
            echo "drift: zimenv init is missing or stale: $zimenv_home/init.zsh"
            status=1
          fi
          if [ ! -L "$config_link" ]; then
            echo "drift: Zim config link is missing: $config_link"
            status=1
          elif [ "$(readlink -f "$config_link")" != "$(readlink -f "$ZIM_CONFIG_FILE")" ]; then
            echo "drift: $config_link does not link to $ZIM_CONFIG_FILE"
            status=1
          fi

          check_block() {
            startup=$1
            marker=$2
            source=$3
            if [ ! -f "$startup" ]; then
              echo "drift: startup file is missing: $startup"
              status=1
              return
            fi
            expected="$(cat "$source")"
            actual="$(sed -n "/^# ${marker} start$/,/^# ${marker} end$/p" "$startup" | sed '1d;$d')"
            if [ "$actual" != "$expected" ]; then
              echo "drift: $marker block in $startup differs from $source"
              status=1
            fi
          }
          check_block "$zshenv" "{{NAME}}-zimenv" "{{DIR}}/etc/zimenv.zsh"
          check_block "$zshrc" "{{NAME}}-zimrc" "{{DIR}}/etc/zimrc.zsh"

          exit "$status"
    ETC_FILES:
      - name: zimenv.zsh
        content: |
          () {
            local ZIM_HOME="${ZIM_ENV_HOME:-{{zim_env_home}}}"
            local ZIM_CONFIG_FILE="${ZIM_ENV_CONFIG:-{{zim_env_config}}}"
            if [[ ! "$ZIM_HOME/init.zsh" -nt "$ZIM_CONFIG_FILE" ]] && ! source {{DIR}}/src/zimfw.zsh init; then
              unfunction zimfw 2>/dev/null || true
              print -u2 "zimenv: failed to rebuild $ZIM_HOME/init.zsh from $ZIM_CONFIG_FILE"
              return
            fi
            source "$ZIM_HOME/init.zsh"
            unfunction zimfw 2>/dev/null || true
          }
      - name: zimrc.zsh
        content: |
          # : is a no-op builtin; ${VAR:=default} sets VAR only if unset or empty
          : ${ZIM_HOME:={{zim_home}}}
          : ${ZIM_CONFIG_FILE:={{ETC}}/zimrc}
          # Install missing modules and update ${ZIM_HOME}/init.zsh if missing or outdated.
          if [[ ! "${ZIM_HOME}/init.zsh" -nt "${ZIM_CONFIG_FILE}" ]]; then
            source {{DIR}}/src/zimfw.zsh init
          fi
          source ${ZIM_HOME}/init.zsh
          export ZSH_AUTOSUGGEST_MANUAL_REBIND=1
    ARCH_PKGS:
      - bat
      - ripgrep
      - eza
  tasks:
    - import_tasks: tasks/compfuzor.includes
