# wanted for nvim-daps's deno support
---
- hosts: all
  vars:
    TYPE: vscode-js-debug
    INSTANCE: git
    REPO: https://github.com/microsoft/vscode-js-debug
    BINS:
      - name: build.sh
        basedir: True
        exec: |
          npm ci
          npm run compile
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
