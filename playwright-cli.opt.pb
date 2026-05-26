---
- hosts: all
  vars:
    REPO_NPM: '@playwright/cli'
  tasks:
    - import_tasks: tasks/compfuzor.includes
