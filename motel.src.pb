---
- hosts: all
  vars:
    REPO: https://github.com/kitlangton/motel
    BUN: True
    BUN_BUILD_SCRIPTS:
      - web:build
    BUN_COMMENT:
      - "prepublishOnly upstream: published @kitlangton/motel ships web/dist,"
      - "which localServer.ts serves (WEB_DIST_DIR). API/TUI work without it."
  tasks:
    - import_tasks: tasks/compfuzor.includes
