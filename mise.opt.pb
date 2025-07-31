---
- hosts: all
  vars:
    TYPE: mise
    INSTANCE: main
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
    ENV:
      - zsh_rc
      - zsh_profile
      - bash_rc
      - bash_profile
    BINS:
      - name: install.user.sh
        content: |
          block-in-file -n mise -C -i {{DIR}}/etc/mise.zshrc -o "${ZSH_RC:-{{zsh_rc}}}"
          block-in-file -n mise -C -i {{DIR}}/etc/mise.zprofile -o "${ZSH_PROFILE:-{{zsh_profile}}}"
      - name: install-bash.user.sh
        content: |
          block-in-file -n mise -C -i {{DIR}}/etc/mise.bashrc -o "${BASH_RC:-{{bash_rc}}}"
          block-in-file -n mise -C -i {{DIR}}/etc/mise.bash_profile -o "${BASH_PROFILE:-{{bash_profile}}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
