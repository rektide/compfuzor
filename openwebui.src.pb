---
- hosts: all
  vars:
    TYPE: openwebui
    INSTANCE: git
    REPO: https://github.com/open-webui/open-webui
    BINS:
      - name: build.sh
        content: |
          uv sync
          pnpm install
          pnpm build
  tasks:
    - import_tasks: tasks/compfuzor.includes
