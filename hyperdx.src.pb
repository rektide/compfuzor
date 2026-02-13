---
- hosts: all
  vars:
    REPO: https://github.com/hyperdxio/hyperdx
    NODEJS: True
    TOOL_VERSIONS:
      yarn: True
    BINS:
      - name: build.sh
        generatedAt: False
        content: |
          yarn install
          yarn build:common-utils
          yarn build:clickhouse
          (
            cd packages/otel-collector
            go build -o migrate ./cmd/migrate
          )
  tasks:
    - import_tasks: tasks/compfuzor.includes
