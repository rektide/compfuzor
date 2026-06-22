---
- hosts: all
  vars:
    REPO: https://tangled.org/ptr.pet/hydrant
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
