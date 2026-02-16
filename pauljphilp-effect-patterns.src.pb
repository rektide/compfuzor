---
- hosts: all
  vars:
    REPO: https://github.com/PaulJPhilp/EffectPatterns
    BUN: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
