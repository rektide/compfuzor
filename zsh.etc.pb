---
- hosts: all
  #gather_facts: False
  vars:
    # 1. System config: install zsh packages and set system default shell.
    #    The lineinfile entries below patch /etc/default/useradd and
    #    /etc/adduser.conf so new users get /bin/zsh.
    SHARES_DIR: /usr/local/share
    PKGS:
      - zsh
      - zsh-doc
    ETC: /etc/zsh
    # files/zsh/zshrc and files/zsh/zshenv were templates intended to replace
    # the Debian system /etc/zsh/{zshrc,zshenv}. They added:
    #   zshrc: key bindings + fpath setup for zfunc.d + zsource-all for z.d
    #   zshenv: locale exports + sourcing XDG env/env.d
    # They were never deployed -- compfuzor's etc type puts DIR at /etc/opt/<name>
    # not /etc/zsh/, and the playbook never wired them to /etc/zsh/ either.
    # User-level init is now handled by zim (zim.opt.pb) + conf.d dropins.
    # The z.d/zfunc.d loading they attempted is superseded by zim modules.
    # 2. Site-level zsh content: deploy z.d/, zfunc.d/, bin/ into /etc/opt/zsh-main/.
    #    The system blocks below (zshrc-site-funcs, zshrc-site-source) wire these
    #    into /etc/zsh/zshrc so they actually get sourced at runtime.
    ETC_DIRS:
      - z.d
      - zfunc.d
      - bin
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
      - z.d/handjam
      - z.d/prompt
      - bin/jtc
      # atuin-session removed: superseded by rektide/zim-atuin-session zim module
      - z.d/user-bin-path
      # System /etc/zsh/ block injections: inline content blocks injected into
      # the Debian system zsh init files via block-in-file (see install-system.sh).
      # Each block does one thing. This replaces the old wholesale file templates.
      - name: zshenv-locale
        content: |
          export LC_ALL=en_US.UTF-8
          export LANG=en_US.UTF-8
          export LANGUAGE=en_US.UTF-8
      - name: zshenv-xdg
        content: |
          for _env in ${XDG_CONFIG_HOME:-$HOME/.config}/env{,.d}(#qN/); do
          	source $_env
          done
          unset _env
      - name: zshenv-user-bin-path
        content: |
          [[ -d "$HOME/.local/bin" ]] && { path=("$HOME/.local/bin" $path); typeset -U path; }
      - name: zshrc-site-funcs
        content: |
          fpath=({{DIR}}/zfunc.d $fpath); typeset -U fpath
          autoload -- {{DIR}}/zfunc.d/[^_]*^.zwc(.N:t)
      - name: zshrc-site-source
        content: |
          zsource-all {{DIR}}/z.d
      # 3. Per-user setup templates: these are content blocks that install-user.sh
      #    stamps into place via block-in-file, not standalone sourced files.
      #    install-user-confd.zsh -> injected into ~/.zshrc, sources conf.d/*.conf
      #    install-share-confd.conf -> injected into conf.d/zsh-main.conf, sources DIR/share/*.conf
      - name: install-user-confd.zsh
        content: |
          _user_zsh_conf_d="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/conf.d"
          if [ -d "$_user_zsh_conf_d" ]; then
            for _user_zsh_conf in "$_user_zsh_conf_d"/*.conf; do
              [ -f "$_user_zsh_conf" ] && source "$_user_zsh_conf"
            done
          fi
          unset _user_zsh_conf _user_zsh_conf_d
      - name: install-share-confd.conf
        content: |
          for _zsh_share_conf in "{{DIR}}/share/"*.conf(N); do
            source "$_zsh_share_conf"
          done
          unset _zsh_share_conf
    # 4. Per-user setup: install-user.sh creates ~/.config/zsh/conf.d/ and injects
    #    two block-in-file entries into ~/.zshrc. Runtime loading chain:
    #      ~/.zshrc -> conf.d/*.conf -> {jj-bookhook, linkem, zsh-main -> share/*.conf}
    BINS:
      - name: install-system.sh
        basedir: False
        become: true
        content: |
          block-in-file -n "{{NAME}}-locale" -i "{{DIR}}/etc/zshenv-locale" -o /etc/zsh/zshenv
          block-in-file -n "{{NAME}}-xdg" -i "{{DIR}}/etc/zshenv-xdg" -o /etc/zsh/zshenv
          block-in-file -n "{{NAME}}-user-bin-path" -i "{{DIR}}/etc/zshenv-user-bin-path" -o /etc/zsh/zshenv
          block-in-file -n "{{NAME}}-site-funcs" -i "{{DIR}}/etc/zshrc-site-funcs" -o /etc/zsh/zshrc
          block-in-file -n "{{NAME}}-site-source" -i "{{DIR}}/etc/zshrc-site-source" -o /etc/zsh/zshrc
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
   tasks:
    - import_tasks: tasks/compfuzor.includes
