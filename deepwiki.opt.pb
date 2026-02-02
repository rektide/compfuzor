---
- hosts: all
  vars:
    #MCP_URL: https://mcp.deepwiki.com/sse
    MCP_URL: https://mcp.deepwiki.com/mcp
  tasks:
    - import_tasks: tasks/compfuzor.includes
