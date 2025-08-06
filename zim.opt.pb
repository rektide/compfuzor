---
- hosts: all
  vars:
    TYPE: zim
    INSTANCE: main
    GET_URL: https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
    zim_home: "$HOME/.cache/zim"
    zim_config_file: "$HOME/.config/zsh/zimrc"
    ENV:
      - zim_home
      - zim_config_file
    BINS:
      - name: install.user.sh
        basedir: False
        content: 
          block-in-file -n {{NAME}} -i {{DIR}}/etc/zim.zsh -o ${ZDOTDIR:-$HOME}/.zshrc
    ETC_FILES:
      - name: zim.zsh
        content: |
          ZIM_CONFIG_FILE="${ZIM_CONFIG_FILE:-{{zim_config_file}}}"
          ZIM_HOME="${ZIM_HOME:-{{zim_home}}}"
          source ${ZIM_HOME:-{{zim_home}}}/init.zsh
          # Install missing modules and update ${ZIM_HOME}/init.zsh if missing or outdated.
          if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]]; then
            source ${ZIM_HOME}/zimfw.zsh init
          fi
      - name: zimrc
        content: |
          # Module
          # Sets sane Zsh built-in environment options.
          zmodule environment
          # Applies correct bindkeys for input events.
          zmodule input
          # Utility aliases and functions. Adds colour to ls, grep and less.
          zmodule utility
          
          # Prompt
          ## Exposes to prompts how long the last command took to execute, used by asciiship.
          #zmodule duration-info
          ## Exposes git repository status information to prompts, used by asciiship.
          #zmodule git-info
          ## A heavily reduced, ASCII-only version of the Spaceship and Starship prompts.
          #zmodule asciiship
          #zmodule https://gitlab.com/Spriithy/basher.git
          #zmodule spaceship-prompt/spaceship-prompt --name spaceship --no-submodules
          zmodule sindresorhus/pure --source async.zsh --source pure.zsh
          
          # Completion
          # Additional completion definitions for Zsh.
          zmodule zsh-users/zsh-completions --fpath src
          # Enables and configures smart and extensive tab completion.
          # completion must be sourced after all modules that add completion definitions.
          zmodule completion
          
          # Modules that must be initialized last
          # Fish-like syntax highlighting for Zsh.
          # zsh-users/zsh-syntax-highlighting must be sourced after completion
          zmodule zsh-users/zsh-syntax-highlighting
          # Fish-like autosuggestions for Zsh.
          zmodule zsh-users/zsh-autosuggestions
  tasks:
    - import_tasks: tasks/compfuzor.includes
