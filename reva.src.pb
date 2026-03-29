---
- hosts: all
  vars:
    TYPE: reva
    REPO: https://github.com/cyberkaida/reverse-engineering-assistant
    PYTHON: True
    MCP_COMMAND:
      - mcp-reva
    MCP_ENV:
      GHIDRA_INSTALL_DIR: "${GHIDRA_INSTALL_DIR}"
    ENV:
      GHIDRA_INSTALL_DIR: /opt/ghidra
    BINS:
      - name: build-extension.sh
        content: |
          cd ReVa
          ./gradlew install
  tasks:
    - import_tasks: tasks/compfuzor.includes
