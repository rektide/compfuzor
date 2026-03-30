---
- hosts: all
  vars:
    TYPE: ghidrassist-mcp
    INSTANCE: git
    REPO: https://github.com/symgraph/GhidrAssistMCP
    PKGS:
      - default-jdk
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          gradle -PGHIDRA_INSTALL_DIR=/opt/ghidra buildExtension
      - name: install-user.sh
        basedir: repo
        content: |
          gradle -PGHIDRA_INSTALL_DIR=/opt/ghidra installExtension
  tasks:
    - import_tasks: tasks/compfuzor.includes
