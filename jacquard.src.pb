---
- hosts: all
  vars:
    REPO: https://tangled.org/nonbinary.computer/jacquard
    RUST: True
  tasks: 
    - import_tasks: tasks/compfuzor.includes
