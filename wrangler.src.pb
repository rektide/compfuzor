
---
- hosts: all
  vars:
    TYPE: wrangler
    REPO: https://github.com/cloudflare/workers-sdk
    NODEJS: True
    BINS:
      - name: build.sh
        content: |
          (
            cd packages/wrangler
            pnpm link -g
          )
  tasks:
    - import_tasks: tasks/compfuzor.includes
