---
- hosts: all
  vars:
    REPO: https://github.com/cdk8s-team/cdk8s
  tasks:
    - import_tasks: tasks/compfuzor.includes
