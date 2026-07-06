---
- hosts: all
  vars:
    REPO: https://github.com/NousResearch/hermes-agent
    PYTHON: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
