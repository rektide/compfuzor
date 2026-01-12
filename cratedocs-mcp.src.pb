---
- hosts: all
  vars:
    TYPE: cratedocs-mcp
    INSTANCE: git
    REPO: https://github.com/PromptExecution/rust-cargo-docs-rag-mcp
    MCP_COMMAND:
      - cratedocs
      - stdio
    RUST: True
    RUST_BIN: cratedocs
  tasks:
    - import_tasks: tasks/compfuzor.includes
