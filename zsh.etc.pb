---
- hosts: all
  gather_facts: False
  vars:
    SHARES_DIR: /usr/local/share
    PKGS:
      - zsh
      - zsh-doc
    ETC: /etc/zsh
    ETC_DIRS:
      - z.d
      - zfunc.d
    ETC_FILES:
      - name: default-useradd-shell-rm
        dest: /etc/default/useradd
        regexp: "^SHELL=/bin/(?!zsh)"
        state: absent
        line: SHELL=/bin/zsh
      - name: default-useradd-shell-set
        dest: /etc/default/useradd
        regexp: ^SHELL=/bin/zsh$
        line: SHELL=/bin/zsh
      - name: adduser-default-shell-rm
        dest: /etc/adduser.conf
        regexp: "^DSHELL=/bin/(?!zsh)"
        state: absent
        line: DSHELL=/bin/zsh
      - name: adduser-default-shell-set
        dest: /etc/adduser.conf
        regexp: ^DSHELL=/bin/zsh$
        line: DSHELL=/bin/zsh
      - zfunc.d/flatten
      - zfunc.d/zcompile-all
      - zfunc.d/zsource-all
      - zfunc.d/zautoload-all
      - z.d/handjam
      - z.d/prompt
      - name: user-conf-d.zsh
        content: |
          _user_zsh_conf_d="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/conf.d"
          if [ -d "$_user_zsh_conf_d" ]; then
            for _user_zsh_conf in "$_user_zsh_conf_d"/*.conf; do
              [ -f "$_user_zsh_conf" ] && source "$_user_zsh_conf"
            done
          fi
          unset _user_zsh_conf _user_zsh_conf_d
      - name: share-dropins.conf
        content: |
          for _zsh_share_conf in "{{DIR}}/share/"*.conf; do
            [ -f "$_zsh_share_conf" ] && source "$_zsh_share_conf"
          done
          unset _zsh_share_conf
    SHARE_FILES:
      - name: dropins.conf
        content: |
          for _zsh_dropin in "{{DIR}}/share/"*.conf; do
            [ -f "$_zsh_dropin" ] && source "$_zsh_dropin"
          done
          unset _zsh_dropin
    BINS:
      #- name: precompile-zsh
      #  dest: False
      #  exec: /bin/zsh -lc '. {{ETC}}/zshrc ; zcompile-all {{ETC}}/z.d {{ETC}}/zfunc.d'
      - name: install-user.sh
        basedir: False
        content: |
          ZSH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
          ZSH_CONF_D_DIR="$ZSH_CONFIG_DIR/conf.d"
          mkdir -p "$ZSH_CONF_D_DIR"

          block-in-file -n "{{NAME}}-share-dropins" -i "{{DIR}}/etc/share-dropins.conf" -o "$ZSH_CONF_D_DIR/{{NAME}}.conf"
          block-in-file -n "{{NAME}}-user-conf-d" -i "{{DIR}}/etc/user-conf-d.zsh" -o "${ZDOTDIR:-$HOME}/.zshrc"
      - name: zimfw-dropins-block.sh
        basedir: False
        content: |
          #!/bin/sh
          ZIMFW_D_DIR="${1:-${ZIMFW_D_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zim/zimfw.d}}"

          for _zimfw_dropin in "$ZIMFW_D_DIR"/*.zimfw "{{DIR}}/share/"*.zimfw; do
            [ -f "$_zimfw_dropin" ] || continue
            printf '\n# from %s\n' "$_zimfw_dropin"
            cat "$_zimfw_dropin"
          done

          unset _zimfw_dropin
      - name: install-zimfw.sh
        basedir: False
        content: |
          ZIMRC="${ZIM_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zimrc}"
          ZIMFW_D_DIR="${ZIMFW_D_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zim/zimfw.d}"

          mkdir -p "$(dirname "$ZIMRC")" "$ZIMFW_D_DIR"
          block-in-file -n "{{NAME}}-zimfw-dropins" -i <("{{DIR}}/bin/zimfw-dropins-block.sh" "$ZIMFW_D_DIR") -o "$ZIMRC"
  tasks:
    - import_tasks: tasks/compfuzor.includes
