---
- hosts: all
  vars:
    NPM: '@playwright/cli'
  tasks:
    - import_tasks: tasks/compfuzor.includes
