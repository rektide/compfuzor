---
- hosts: all
  vars:
    REPO: https://github.com/kitlangton/motel
    BUN: True
    BINS:
      - name: build.sh
        run: True
        basedir: repo
        content: |
          bun install
          # prepublishOnly upstream: published @kitlangton/motel ships web/dist,
          # which localServer.ts serves (WEB_DIST_DIR). API/TUI work without it.
          bun run web:build
  tasks:
    - import_tasks: tasks/compfuzor.includes
