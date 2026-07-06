---
- hosts: all
  vars:
    TYPE: claude-code
    INSTANCE: main
    NPM: "@anthropic-ai/claude-code"
    NPM_ALLOW_BUILD: True
    #NPM_SRC: true
    #NPM_PACKAGE_BIN: claude
  tasks:
    - import_tasks: tasks/compfuzor.includes
