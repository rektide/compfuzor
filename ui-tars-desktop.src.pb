---
- hosts: all
  vars:
    REPO: https://github.com/bytedance/UI-TARS-desktop
    BINS:
      - name: build.sh
        content: |
          pnpm i --frozen-lockfile
          cd packages/ui-tars/cli
          pnpm i --frozen-lockfile
          pnpm link
          cd ../../..
          cd multimodal/agent-tars/cli
          pnpm i --frozen-lockfile
          pnpm link
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
