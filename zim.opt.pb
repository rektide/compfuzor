---
- hosts: all
  vars:
    TYPE: zim
    INSTANCE: main
    CONFIG_KEY: zimfw
    CONFIG_MERGE: block-in-file
    zim_home: "$HOME/.cache/zim"
    ENV_LIST:
      - zim_home
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
          {{DIR}}/bin/config.sh
          block-in-file -n {{NAME}} -i {{DIR}}/etc/zim.zsh -o ${ZDOTDIR:-$HOME}/.zshrc --envsubst
    ETC_FILES:
      - name: zim.zsh
        content: |
          # : is a no-op builtin; ${VAR:=default} sets VAR only if unset or empty
          : ${ZIM_HOME:={{zim_home}}}
          : ${ZIM_CONFIG_FILE:=${DIR}/etc/${CONFIG_KEY}.${CONFIG_EXT}}
          # Install missing modules and update ${ZIM_HOME}/init.zsh if missing or outdated.
          if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE} ]]; then
            source {{DIR}}/src/zimfw.zsh init
          fi
          source ${ZIM_HOME}/init.zsh
      - name: zimfw/01-core.conf
        content: |
          # Module
          # Sets sane Zsh built-in environment options.
          zmodule environment
          # Applies correct bindkeys for input events.
          zmodule input
          # Utility aliases and functions. Adds colour to ls, grep and less.
          zmodule utility
      - name: zimfw/02-mise.conf
        content: |
          zmodule https://github.com/joke/zim-mise
      - name: zimfw/03-prompt.conf
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
          #zmodule sorin
          #zmodule agnoster
          #zmodule eriner
          zmodule minimal
          zmodule magic-enter
      - name: zimfw/04-tools.conf
        content: |
          # More
          zmodule exa
          zmodule fzf
          zmodule git
          zmodule k
          zmodule termtitle
          zmodule https://github.com/hmgle/aider-zsh-complete
          #zmodule https://github.com/jnooree/zoxide-zsh-completion
          zmodule kiesman99/zim-zoxide
          #zmodule https://github.com/agkozak/zsh-z
          #zmodule https://github.com/joke/zim-helm
          #zmodule https://github.com/joke/zim-github-cli
          #zmodule https://github.com/joke/zim-kn
          zmodule https://github.com/joke/zim-kubectl
          #zmodule https://github.com/joke/zim-k9s
          #zmodule https://github.com/joke/zim-skaffold
          #zmodule https://github.com/joke/zim-yq
          zmodule https://github.com/lipov3cz3k/zsh-uv
          #zmodule https://github.com/MichaelAquilina/zsh-you-should-use
          #zmodule https://github.com/pressdarling/codex-zsh-plugin
          # also needs: zstyle ':zim:plugins:alias-finder' autoload yes
          zmodule https://github.com/shanwker1223/zim-alias-finder
          zmodule https://github.com/shihanng/zim-atuin
          #zmodule https://github.com/shihanng/zim-kustomize
          #zmodule https://raw.githubusercontent.com/sheax0r/etcdctl-zsh/refs/heads/master/_etcdctl
          #zmodule https://codeberg.org/iff/pay-respects
      - name: zimfw/05-completions.conf
        content: |
          # Completion
          # Additional completion definitions for Zsh.
          zmodule zsh-users/zsh-completions --fpath src
          zmodule rektide/zim-niri
          zmodule rektide/zim-beads
          zmodule rektide/zim-jaeger
          zmodule rektide/zim-timoni
          # Enables and configures smart and extensive tab completion.
          # completion must be sourced after all modules that add completion definitions.
          zmodule completion
      - name: zimfw/06-late.conf
        content: |
          # Modules that must be initialized last
          # Fish-like syntax highlighting for Zsh.
          # zsh-users/zsh-syntax-highlighting must be sourced after completion
          zmodule zsh-users/zsh-syntax-highlighting
          # Fish-like autosuggestions for Zsh.
          zmodule zsh-users/zsh-autosuggestions
          zmodule https://github.com/lukechilds/zsh-better-npm-completion
    ARCH_PKGS:
      - bat
      - ripgrep
      - eza
  tasks:
    - import_tasks: tasks/compfuzor.includes
