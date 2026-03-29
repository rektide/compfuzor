---
- hosts: all
  vars:
    TYPE: reva
    REPO: https://github.com/cyberkaida/reverse-engineering-assistant
    PYTHON: True
    MCP_URL: "http://localhost:8080/mcp/message"
    ENV:
      GHIDRA_INSTALL_DIR: /opt/ghidra
    BINS:
      - name: build-extension.sh
        content: |
          cd ReVa
          ./gradlew install
  tasks:
    - import_tasks: tasks/compfuzor.includes
