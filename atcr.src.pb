---
- hosts: all
  vars:
    REPO: https://tangled.org/evan.jarrett.net/at-container-registry
  tasks:
    - import_tasks: tasks/compfuzor.includes
