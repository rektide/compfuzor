---
- hosts: all
  vars:
    TYPE: amp
    INSTANCE: main
    NPM_PACKAGE: '@sourcegraph/amp@latest'
  tasks:
    - import_tasks: tasks/compfuzor.includes
