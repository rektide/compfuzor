---
- hosts: all
  vars:
    REPO: https://github.com/cloudflare/cloudflare-os
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
