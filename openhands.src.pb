---
- hosts: all
  vars:
    REPO: https://github.com/OpenHands/OpenHands
    TOOL_VERSIONS:
      nodejs: True
      python: True
    BINS:
      - name: build.sh
        content: |
          make build
  tasks:
    - import_tasks: tasks/compfuzor.includes

