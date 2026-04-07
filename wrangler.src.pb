---
- hosts: all
  vars:
    TYPE: wrangler
    REPO: https://github.com/cloudflare/workers-sdk
    NODEJS: True
    NODEJS_LINK_DIR: packages/wrangler
  tasks:
    - import_tasks: tasks/compfuzor.includes
