---
- hosts: all
  vars:
    TYPE: block-in-file
    INSTANCE: git
    REPO: https://github.com/jauntywunderkind/block-in-file
    ETC_FILES:
      - name: tool-versions
        content: |
          deno 2
    BINS:
      - name: install.sh
        basedir: repo
        run: True
        content: |
          [ ! -f '.tool-versions' ] && ln -s etc/tool-versions .tool-versions

          echo deno install
          mise x -- deno install
          echo

          echo deno install --global
          # deno automatically adds "/bin" to the path so pre-remove our copy of it
          ROOT=$(dirname $GLOBAL_BINS_DIR) deno task install:dir
      - name: blockinfile
        basedir: False
        content: |
          realdir="$(pwd)"
          cd "{{DIR}}"
          mise x --cd "$realdir" -- deno run block-in-file $*
    ENV:
      GLOBAL_BINS_DIR: "{{GLOBAL_BINS_DIR}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
