---
- hosts: all
  vars:
    REPO: https://github.com/clawdbot/clawdbot
    NODEJS: True
    BINS:
      - name: build.sh
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
