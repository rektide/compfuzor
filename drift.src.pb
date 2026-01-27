---
- hosts: all
  vars:
    REPO: https://github.com/dadbodgeoff/drift
    NODEJS: True
    MCP_COMMAND:
      - driftdetect-mcp
  tasks:
    - import_tasks: tasks/compfuzor.includes
