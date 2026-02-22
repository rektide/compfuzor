---
- hosts: all
  vars:
    #MCP_URL: https://mcp.devin.ai/mcp
    MCP_URL: https://mcp.devin.ai/sse
    MCP_HEADERS:
      Authorization: "Bearer ${DEVIN_AI_API_KEY}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
