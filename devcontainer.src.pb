---
- hosts: all
  vars:
    TYPE: devcontainer
    REPO: https://github.com/devcontainers/cli
    NODEJS: True
    NODEJS_BUILD_SCRIPT: compile
  tasks:
    - import_tasks: tasks/compfuzor.includes
