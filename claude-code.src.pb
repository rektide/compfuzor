---
- hosts: all
  vars:
    TYPE: claude-code
    INSTANCE: main
    TOOL_VERSIONS:
      node: "{{NODE_VERSION}}"
      pnpm: "{{PNPM_VERSION}}"
    NPM_PACKAGE: "@anthropic-ai/claude-code"
    NPM_PACKAGE_BIN: claude
  tasks:
    - import_tasks: tasks/compfuzor.includes
