---
- hosts: all
  vars:
    REPO: https://github.com/huggingface/candle
  tasks:
    - import_tasks: tasks/compfuzor.includes
