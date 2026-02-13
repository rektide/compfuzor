---
- hosts: all
  vars:
    TYPE: git
    INSTANCE: main
    ENV:
      B: main
      BOOKMARK: main
    SHARE_FILES:
      - name: git_branch.zsh
        content: |
          # Get current git branch name
          git_branch() {
            ref=$(git symbolic-ref HEAD 2>/dev/null | cut -d'/' -f3)
            echo $ref
          }
      - name: addTngl.zsh
        content: |
          # Add tangled.sh remote to jujutsu repo
          addTngl() {
            jj git remote add tngl "tngl:jauntywk.bsky.social/${DIR:-$(basename "$(pwd)")}"
            jj bookmark track main --remote=tngl
          }
      - name: pushIt.zsh
        content: |
          # Push to multiple remotes (tngl, rektide, github, origin)
          pushIt() {
            jj bookmark set $B -r @- --allow-backwards

            jj git remote list | awk '{print $1}' | grep -q "tngl" && jj git push -b $B --remote tngl &
            jj git remote list | awk '{print $1}' | grep -q "rektide" && jj git push -b $B --remote rektide &
            jj git remote list | awk '{print $1}' | grep -q "github" && jj git push -b $B --remote github &

            if ! (jj git remote list | awk '{print $1}' | grep -q "rektide\|github") || ! jj git remote list | grep "^origin" | grep -q "github\.com"; then
              jj git push -b $B &
            fi
          }
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/{{NAME}}"
          mkdir -p "$CONFIG_DIR"

          # Link all shell scripts from share/ to user config
          for script in "{{DIR}}/share/"*.zsh; do
            [ -f "$script" ] || continue
            scriptname=$(basename "$script")
            ln -sfv "$script" "$CONFIG_DIR/$scriptname"
          done
          ln -sfv "{{DIR}}/env.export" $CONFIG_DIR/00-env-{{NAME}}.zsh
  tasks:
    - import_tasks: tasks/compfuzor.includes
