---
- hosts: all
  vars:
    TYPE: opencode
    INSTANCE: git
    REPO: https://github.com/sst/opencode
    ETC_FILES:
      - name: tool-versions
        content: |
          bun 1
          go 1
    BINS:
      - name: install.sh
        content: |
          [ ! -f '.tool-versions' ] && ln -s etc/tool-versions .tool-versions
          bun install --frozen-lockfile
          mkdir -p ~/.local/share/opencode/log
      - name: opencode
        basedir: False
        global: True
        content: |
          exec bun run --cwd $DIR dev $(pwd)
  tasks:
    - import_tasks: tasks/compfuzor.includes
