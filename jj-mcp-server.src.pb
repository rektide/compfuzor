---
- hosts: all
  vars:
    REPO: https://github.com/mcginleyr1/jj-mcp-server
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
