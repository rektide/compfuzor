---
- hosts: all
  vars:
    TYPE: zim
    INSTANCE: main
    CONFIG_KEY: zimfw
    CONFIG_MERGE: block-in-file
    ZIM_HOST: true
    zim_home: "$HOME/.cache/zim"
    zim_config_link: "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/{{CONFIG_KEY}}.{{CONFIG_EXT}}"
    ENV_LIST:
      - zim_home
      - zim_config_link
    GET_URLS:
      - https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
    PKGS:
      - bat
      - eza
      - fzf
      - zoxide
    # Zim module declaration. gen_zim renders one fragment per module under
    # etc/zim/ (etc/zim-disabled/ for enabled:false); install-zim.sh promotes
    # them into etc/zimfw/ and config.sh (block-in-file) assembles zimfw.conf
    # in sorted filename order. `phase` is a name (core/prompt/tools/
    # completion/late) or a number 00-99 for fine placement between bands.
    ZIM_MODULES:
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
      - source: https://github.com/rektide/zim-mise
        phase: core
        comment: included early so other tools can benefit

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
      - source: https://github.com/joke/zim-mise
        phase: tools
        enabled: false
        comment: mise included above to be early
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
      - name: install-user.sh
        basedir: False
        content: |
          echo promoting zim fragments
          {{DIR}}/bin/install-zim.sh {{DIR}}
          if [[ -f "${CONFIG_OUTPUT}" ]]
          then
            echo "using existing zimrc (config.sh to rebuild)"
          else
            echo running config.sh to generate zimrc
            {{DIR}}/bin/config.sh
            echo
          fi
          echo installing zshrc config
          block-in-file -n {{NAME}} -i {{DIR}}/etc/zim.zsh -o ${ZDOTDIR:-$HOME}/.zshrc
          echo symlinking zimrc
          mkdir -p "$(dirname "${ZIM_CONFIG_LINK:-{{zim_config_link}}}")"
          ln -sfv "${CONFIG_OUTPUT}" "${ZIM_CONFIG_LINK:-{{zim_config_link}}}"
      - name: status.sh
        basedir: False
        content: |
          status=0
          config_link="${ZIM_CONFIG_LINK:-{{zim_config_link}}}"
          zshrc="${ZDOTDIR:-$HOME}/.zshrc"
          marker="{{NAME}}"

          if [ ! -f "$CONFIG_OUTPUT" ]; then
            echo "drift: generated Zim config is missing: $CONFIG_OUTPUT"
            status=1
          elif [ ! -L "$config_link" ]; then
            echo "drift: Zim config link is missing: $config_link"
            status=1
          elif [ "$(readlink -f "$config_link")" != "$(readlink -f "$CONFIG_OUTPUT")" ]; then
            echo "drift: $config_link does not link to $CONFIG_OUTPUT"
            status=1
          fi

          if [ ! -f "$zshrc" ]; then
            echo "drift: zshrc is missing: $zshrc"
            status=1
          else
            expected="$(cat "{{DIR}}/etc/zim.zsh")"
            actual="$(sed -n "/^# ${marker} start$/,/^# ${marker} end$/p" "$zshrc" | sed '1d;$d')"
            if [ "$actual" != "$expected" ]; then
              echo "drift: Zim block in $zshrc differs from {{DIR}}/etc/zim.zsh"
              status=1
            fi
          fi

          exit "$status"
    ETC_FILES:
      - name: zim.zsh
        content: |
          # : is a no-op builtin; ${VAR:=default} sets VAR only if unset or empty
          : ${ZIM_HOME:={{zim_home}}}
          : ${ZIM_CONFIG_FILE:={{DIR}}/etc/{{CONFIG_KEY}}.{{CONFIG_EXT}}}
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
