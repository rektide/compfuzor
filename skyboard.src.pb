---
- hosts: all
  vars:
    REPO: https://github.com/disnet/skyboard
    NODEJS: True
    BINS:
      - name: build.sh
        basedir: repo/cli
        content: |
          (cd ..; pnpm i)
      - name: install.sh
        basedir: repo/cli
  tasks:
    - import_tasks: tasks/compfuzor.includes
