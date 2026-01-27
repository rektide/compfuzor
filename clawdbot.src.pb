---
- hosts: all
  vars:
    REPO: https://github.com/clawdbot/clawdbot
    NODEJS: True
    PKGS:
      - node-gyp
      - node-addon-api
    BINS:
      - name: build.sh
        generatedAt: skip
        content: |
          pnpm install
          pnpm ui:build
          pnpm build
      - name: dev.sh
        content: |
          pnpm gateway:watch
      - name: install.sh
        content: |
          pnpm clawdbot onboard --install-daemon
  tasks:
    - import_tasks: tasks/compfuzor.includes
