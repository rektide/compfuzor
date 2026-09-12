---
- hosts: all
  vars:
    TYPE: zim
    INSTANCE: main
    ZIM_HOST: true
    zim_home: "$HOME/.cache/zim"
    zim_env_home: "$HOME/.cache/zim-env"
    zim_config_default: "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimrc"
    zim_env_config_default: "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimenv"
    zim_config_link: "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimfw.conf"
    ZIM_CONFIG_INSTALL: assemble
    ZIM_CONFIG_DROPINS: link
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
    CONFIG_CONTEXTS:
      user:
        scope: user
        root: config
        subpath: zsh
        install: "{{ ZIM_CONFIG_INSTALL }}"
        dropins: "{{ ZIM_CONFIG_DROPINS }}"
        compose: false
        configs:
          zimrc:
            output:
              env: ZIM_CONFIG_FILE
              default: zimrc
              ignore:
                - "{{ ETC }}/zimrc"
                - "{{ DIR }}/etc/zimrc"
          zimenv:
            output:
              env: ZIM_ENV_CONFIG
              default: zimenv
              ignore:
                - "{{ ETC }}/zimenv"
                - "{{ DIR }}/etc/zimenv"
    ENV: {}
    ENV_LIST:
      - zim_home
      - zim_env_home
    ZIM_CONTEXT: user
    ZIM_CONTEXTS:
      user:
        config: user
    GET_URLS:
      - https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
    PKGS:
      - bat
      - eza
      - fzf
      - zoxide
    # Host Zim modules render directly into canonical zimrc.d/zimenv.d inputs;
    # nonhost contributors retain etc/zim/<channel>/{active,disabled} for
    # explicit donor-admin or consumer-local import. `phase` is a name (core/prompt/tools/
    # completion/late) or a number 00-99 for fine placement between bands.
    ZIM_MODULES:
      - name: emergency
        source: emergency.zsh
        phase: 99
        comment: Reversible low-I/O shell mode; `_emergency` dispatches `_emergency_<name>_on/_off` pairs, globally or per subsystem (`_emergency atuin off`).

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
    ETC_FILES:
      - name: zimenv.zsh
        content: |
          [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]] && return
          () {
            local ZIM_HOME="${ZIM_ENV_HOME:-{{zim_env_home}}}"
            local config="${ZIM_ENV_CONFIG:-}"
            case "$config" in "{{ETC}}/zimenv"|"{{DIR}}/etc/zimenv") config="" ;; esac
            local ZIM_CONFIG_FILE="${config:-{{zim_env_config_default}}}"
            if [[ ! "$ZIM_HOME/init.zsh" -nt "$ZIM_CONFIG_FILE" ]] && ! source "{{DIR}}/src/zimfw.zsh" init; then
              unfunction zimfw 2>/dev/null || true
              print -u2 "zimenv: failed to rebuild $ZIM_HOME/init.zsh from $ZIM_CONFIG_FILE"
              return
            fi
            source "$ZIM_HOME/init.zsh"
            unfunction zimfw 2>/dev/null || true
          }
      - name: zimrc.zsh
        content: |
          if [[ ${COMPFUZOR_EMERGENCY:-0} == 1 ]]; then
            typeset -g _COMPFUZOR_EMERGENCY_COLD=1
            source "{{ETC}}/zim-modules/emergency/init.zsh"
            return
          fi
          # : is a no-op builtin; ${VAR:=default} sets VAR only if unset or empty
          : ${ZIM_HOME:={{zim_home}}}
          case "${ZIM_CONFIG_FILE:-}" in "{{ETC}}/zimrc"|"{{DIR}}/etc/zimrc") unset ZIM_CONFIG_FILE ;; esac
          : ${ZIM_CONFIG_FILE:={{zim_config_default}}}
          # Install missing modules and update ${ZIM_HOME}/init.zsh if missing or outdated.
          if [[ ! "${ZIM_HOME}/init.zsh" -nt "${ZIM_CONFIG_FILE}" ]]; then
            source "{{DIR}}/src/zimfw.zsh" init
          fi
          source ${ZIM_HOME}/init.zsh
          export ZSH_AUTOSUGGEST_MANUAL_REBIND=1
    ARCH_PKGS:
      - bat
      - ripgrep
      - eza
  tasks:
    - import_tasks: tasks/compfuzor.includes
