---
- hosts: all
  vars:
    REPO: https://github.com/openchamber/openchamber
    BUN: True
    BINS:
      - name: build.sh
        content: |
          bun run build
          (
            cd packages/desktop
            bun run tauri build
          )
          (
            cd packages/vscode
            bunx vsce package --no-dependencies
          )
      - name: install.sh
        content: |
          (
            cd packages/desktop/src-tauri/target/release
            ln -sfv $(pwd) $GLOBAL_BINS_DIR/
          )
      - name: install-vscode-user.sh
        basedir: repo
        content: |
          code --install-extension packages/vscode/openchamber-*.vsix
  tasks:
    - import_tasks: tasks/compfuzor.includes
