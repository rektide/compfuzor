---
- hosts: all
  vars:
    TYPE: asdf-yarn
    INSTANCE: main
    BINS:
      - name: install.user.sh
        exec: |
          asdf plugin-add yarn
          asdf install yarn latest
          if ! test -f ~/.tool-versions || ! grep -q asdf ~/.tool-versions; then
            asdf global yarn latest
          fi
  tasks:
    - include: tasks/compfuzor.includes type=opt
