---
- hosts: all
  vars:
    REPO: https://github.com/Basekick-Labs/arc
    GO: True
    BINS:
      - name: install.sh
        generatedAt: False
        content: |
          make build
  tasks:
    - import_tasks: tasks/compfuzor.includes
