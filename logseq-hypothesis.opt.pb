---
- hosts: all
  vars:
    TYPE: logseq-hypothesis
    INSTANCE: giot
    REPO: https://github.com/c6p/logseq-hypothesis
    BINS:
      - name: build.sh
        exec: |
          pnpm install && \
          pnpm build
          # "Load unpacked plugin" in client
  tasks:
    - include: tasks/compfuzor.includes type=opt
