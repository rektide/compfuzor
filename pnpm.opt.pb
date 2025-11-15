---
- hosts: all
  vars:
    TYPE: pnpm
    INSTANCE: main
    TOOL_VERSIONS:
      pnpm: 10
    BINS:
      - name: install-user.sh
        content: |
          block-in-file -n '{{TYPE}}' -i etc/.tool-versions $HOME/.tool-versions -C
          if command -v mise
          then
            (cd $HOME; mise install)
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
