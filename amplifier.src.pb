---
- hosts: all
  vars:
    TYPE: amplifier
    INSTANCE: git
    REPO: https://github.com/microsoft/amplifier
    TOOL_VERSIONS:
      pnpm: True
      nodejs: True
    BINS:
      - name: build.sh
        content: |
          #make install
          uv sync --group dev
  tasks:
    - import_tasks: tasks/compfuzor.includes

