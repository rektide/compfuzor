---
- hosts: all
  vars:
    TYPE: git
    INSTANCE: main
    # zsh delivery is via zimfw modules (gen_zim): git-env uses the env kind,
    # git-helpers the functions kind (bodies declared inline -- no files/
    # needed). install-zimfw.sh imports fragments into the effective host context.
    ZIM_MODULES:
      - name: git-env
        phase: tools
        env:
          B: main
          BOOKMARK: main
        comment: default bookmark for pushIt et al (stomp-guarded)
      - name: git-helpers
        phase: tools
        functions:
          git_branch: |
            ref=$(git symbolic-ref HEAD 2>/dev/null | cut -d'/' -f3)
            echo $ref
          addTngl: |
            jj git remote add tngl "tngl:jauntywk.bsky.social/${DIR:-$(basename "$(pwd)")}"
            jj bookmark track main --remote=tngl
          pushIt: |
            jj bookmark set $B -r @- --allow-backwards

            jj git remote list | awk '{print $1}' | grep -q "tngl" && jj git push -b $B --remote tngl &
            jj git remote list | awk '{print $1}' | grep -q "rektide" && jj git push -b $B --remote rektide &
            jj git remote list | awk '{print $1}' | grep -q "github" && jj git push -b $B --remote github &

            if ! (jj git remote list | awk '{print $1}' | grep -q "rektide\|github") || ! jj git remote list | grep "^origin" | grep -q "github\.com"; then
              jj git push -b $B &
            fi
        comment: jj/git push helpers
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
