---
- hosts: all
  vars:
    TYPE: raux
    INSTANCE: git
    REPO: https://github.com/aigdat/raux
    BINS:
      - name: build.sh
        content: |
          pnpm install
          pnpm build
  tasks:
    - import_tasks: tasks/compfuzor.includes
