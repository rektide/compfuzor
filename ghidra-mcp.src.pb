---
- hosts: all
  vars:
    TYPE: ghidra-mcp
    REPO: https://github.com/bethington/ghidra-mcp
    MCP_COMMAND:
      - ghidra-mcp
    MCP_ENV:
      GHIDRA_MCP_URL: "${GHIDRA_MCP_URL}"
      GHIDRA_MCP_LOG_LEVEL: "${GHIDRA_MCP_LOG_LEVEL}"
    ENV:
      GHIDRA_MCP_URL: "http://127.0.0.1:8089"
      GHIDRA_MCP_LOG_LEVEL: "INFO"
    BINS:
      - name: ghidra-mcp
        global: True
        content: |
          exec uv run "$DIR/bridge_mcp_ghidra.py"
  tasks:
    - import_tasks: tasks/compfuzor.includes
