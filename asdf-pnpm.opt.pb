---
- hosts: all
  vars:
    TYPE: asdf-pnpm
    INSTANCE: main
    BINS:
      - name: install-user.sh
        exec: |
          asdf plugin-add pnpm
          asdf install pnpm latest
          if ! test -f ~/.tool-versions || ! grep -q pnpm ~/.tool-versions; then
            asdf global pnpm latest
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
