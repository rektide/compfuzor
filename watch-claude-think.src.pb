---
- hosts: all
  vars:
    TYPE: watch-calude-think
    INSTANCE: git
    REPO: https://github.com/bporterfield/watch-claude-think
    BINS:
      - name: build.sh
        content: |
          npm run build
  tasks:
    - import_tasks: tasks/compfuzor.includes
