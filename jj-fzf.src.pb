---
- hosts: all
  vars:
    REPO: https://github.com/tim-janik/jj-fzf
    BINS:
      - name: build.sh
        content: |
          make all
      - name: install-user.sh
        content: |
          make install PREFIX=~/.local
  tasks:
    - import_tasks: tasks/compfuzor.includes
