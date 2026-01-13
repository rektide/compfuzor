---
- hosts: all
  vars:
    REPO: https://github.com/PropterMalone/ergoblock
    NODEJS: True
    BINS:
      - name: build.sh
        content: |
          pnpm install
          pnpm run build
  tasks:
    - import_tasks: tasks/compfuzor.includes
