---
- hosts: all
  vars:
    TYPE: zim
    INSTANCE: main
    CONFIG_KEY: zimfw
    CONFIG_MERGE: block-in-file
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
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
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
      - name: zimfw/01-core.conf
        content: |
          # Module
          # Sets sane Zsh built-in environment options.
          zmodule environment
          # Applies correct bindkeys for input events.
          zmodule input
          # Utility aliases and functions. Adds colour to ls, grep and less.
          zmodule utility
          # included early so other tools can benefit
          zmodule https://github.com/joke/zim-mise
      - name: zimfw/02-prompt.conf
        content: |
          # Prompt
          ## Exposes to prompts how long the last command took to execute, used by asciiship.
          zmodule duration-info
          zmodule git-info
          zmodule prompt-pwd
          ## Exposes git repository status information to prompts, used by asciiship.
          #zmodule git-info
          ## A heavily reduced, ASCII-only version of the Spaceship and Starship prompts.
          #zmodule asciiship
          #zmodule https://gitlab.com/Spriithy/basher.git
          #zmodule spaceship-prompt/spaceship-prompt --name spaceship --no-submodules
          #zmodule sindresorhus/pure --source async.zsh --source pure.zsh
          #zmodule https://github.com/joke/zim-oh-my-posh
          #zmodule https://github.com/joke/zim-starship
          #zmodule sorin
          #zmodule agnoster
          #zmodule eriner
          zmodule minimal
          #zmodule https://codeberg.org/iff/pay-respects
          #zmodule magic-enter
      - name: zimfw/03-tools.conf
        content: |
          # More
          zmodule exa
          zmodule fzf
          zmodule git
          zmodule k
          zmodule termtitle
          #zmodule https://github.com/hmgle/aider-zsh-complete
          # replaced by rektide/zim-zoxide (cached init + completions, no cd override)
          #zmodule https://github.com/jnooree/zoxide-zsh-completion
          #zmodule kiesman99/zim-zoxide  (renamed -> vietz-dev)
          #zmodule vietz-dev/zim-zoxide
          #zmodule antoineco/zim-zoxide
          zmodule rektide/zim-zoxide
          #zmodule https://github.com/agkozak/zsh-z
          #zmodule https://github.com/joke/zim-chezmoi
          zmodule https://github.com/joke/zim-github-cli
          #zmodule https://github.com/joke/zim-gopass
          zmodule https://github.com/joke/zim-helm
          #zmodule https://github.com/joke/zim-istioctl
          #zmodule https://github.com/joke/zim-kn
          zmodule https://github.com/joke/zim-kubectl
          #zmodule https://github.com/joke/zim-k9s
          # mise included above to be early
          #zmodule https://github.com/joke/zim-mise
          #zmodule https://github.com/joke/zim-skaffold
          #zmodule https://github.com/joke/zim-steampipe
          #zmodule https://github.com/joke/zim-yq
          zmodule https://github.com/lipov3cz3k/zsh-uv
          #zmodule https://github.com/MichaelAquilina/zsh-you-should-use
          #zmodule https://github.com/pressdarling/codex-zsh-plugin
          # also needs: zstyle ':zim:plugins:alias-finder' autoload yes
          #zmodule https://github.com/shanwker1223/zim-alias-finder
          #zmodule https://github.com/shihanng/zim-kustomize
          #zmodule https://raw.githubusercontent.com/sheax0r/etcdctl-zsh/refs/heads/master/_etcdctl
          zmodule https://github.com/shihanng/zim-atuin

          zmodule rektide/zim-atuin-session
          zmodule rektide/zim-beads
          zmodule rektide/zim-claude
          zmodule rektide/zim-jaeger
          zmodule rektide/zim-jujutsu
          zmodule rektide/zim-mosh
          zmodule rektide/zim-niri
          zmodule rektide/zim-opencode
          zmodule rektide/zim-timoni
          zmodule rektide/zim-tgo
          zmodule rektide/zim-systemd-envvar
      - name: zimfw/04-completion.conf
        content: |
          # Additional completion definitions for Zsh.
          zmodule zsh-users/zsh-completions --fpath src
          # Enables and configures smart and extensive tab completion, must be sourced
          # after all modules that add completion definitions.
          zmodule completion
      - name: zimfw/05-late.conf
        content: |
          # Modules that must be initialized last

          # Fish-like syntax highlighting for Zsh, must be sourced after completion.
          zmodule zsh-users/zsh-syntax-highlighting
          # Fish-like history search for Zsh, must be sourced after
          # zsh-users/zsh-syntax-highlighting.
          #zmodule zsh-users/zsh-history-substring-search
          # Fish-like autosuggestions for Zsh. Add the following to your ~/.zshrc to boost
          # performance: ZSH_AUTOSUGGEST_MANUAL_REBIND=1
          zmodule zsh-users/zsh-autosuggestions

          zmodule https://github.com/lukechilds/zsh-better-npm-completion
    ARCH_PKGS:
      - bat
      - ripgrep
      - eza
  tasks:
    - import_tasks: tasks/compfuzor.includes
