---
- hosts: all
  vars:
    TYPE: jaeger
    INSTANCE: git
    REPO: https://github.com/jaegertracing/jaeger
    GO: True
    GO_BIN: jaeger
    GO_TARGET: ./cmd/jaeger
    TOOL_VERSIONS:
      go: true
      nodejs: true
    BINS:
      - name: build.sh
        content: |
          make build-ui
  tasks:
    - import_tasks: tasks/compfuzor.includes
