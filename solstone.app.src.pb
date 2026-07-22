---
- hosts: all
  vars:
    TYPE: solstone.app
    INSTANCE: git
    REPO: https://github.com/solpbc/solstone.app.git
    NODEJS: True
    BINS:
      - name: deploy.sh
        exec: |
          wrangler deploy
  tasks:
    - import_tasks: tasks/compfuzor.includes
