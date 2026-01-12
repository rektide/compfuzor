---
- hosts: all
  vars:
    REPO: https://github.com/bartolli/codanna
    RUST: True
    MCP_COMMAND:
      - codanna
      - serve
      - --watch
  tasks:
    - import_tasks: tasks/compfuzor.includes
