---
- hosts: all
  vars:
    REPO: https://github.com/vercel-labs/skills.git
    NODEJS: True
    BINS:
      - name: skills
        global: True
        content: |
          exec node ${DIR}/bin/cli.mjs $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
