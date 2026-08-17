---
- hosts: all
  vars:
    TYPE: git
    INSTANCE: main
    # zsh delivery is via zimfw modules (gen_zim): each .zsh under files/git/
    # becomes a local zim module (ETC/zim-modules/<name>/init.zsh + a zmodule
    # declaration fragment), auto-installed by install-user-zimfw.sh into the
    # zim host assembly. The old route -- SHARE_FILES + install-user.sh
    # symlinking into ~/.config/zsh/{{NAME}}/ -- was dangling: nothing sourced
    # that dir (the zsh.etc.pb conf.d chain covers conf.d/*.conf only).
    ZIM_MODULES:
      - name: git-env
        phase: tools
        env:
          B: main
          BOOKMARK: main
        comment: default bookmark for pushIt et al (stomp-guarded)
      - source: git_branch.zsh
        phase: tools
        comment: git_branch() helper
      - source: addTngl.zsh
        phase: tools
        comment: add tangled.sh remote to a jj repo
      - source: pushIt.zsh
        phase: tools
        comment: push bookmark to all remotes
    BINS:
      - name: cleanup-old-install.sh
        scope: [user]
        basedir: False
        helpers: [env, setopts, loud, report]
        content: |
          _legacy="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/{{NAME}}"
          if [ -d "$_legacy" ]; then
            rm -rfv "$_legacy"
          else
            _cf_report_skip "cleanup-old-install.sh" "no legacy dir at $_legacy"
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
