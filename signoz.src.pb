---
- hosts: all
  vars:
    REPO: https://github.com/SigNoz/signoz
    TOOL_VERSIONS:
      go: True
      nodejs: True
    BINS:
      - name: build.sh
        content:
          make go-build-community
          make js-build
  tasks:
    - import_tasks: tasks/compfuzor.includes
