---
- hosts: all
  vars:
    TYPE: ghidramcp
    REPO: https://github.com/LaurieWired/GhidraMCP
    MCP_COMMAND:
      - ghidramcp
    MCP_ENV:
      GHIDRA_SERVER_URL: "${GHIDRA_SERVER_URL}"
    ENV:
      GHIDRA_SERVER_URL: "http://127.0.0.1:8080/"
    BINS:
      - name: ghidramcp
        global: True
        content: |
          exec uv run "$DIR/bridge_mcp_ghidra.py" --ghidra-server "${GHIDRA_SERVER_URL:-http://127.0.0.1:8080/}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
