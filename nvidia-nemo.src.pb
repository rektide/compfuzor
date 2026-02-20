---
- hosts: all
  vars:
    REPO: https://github.com/NVIDIA-NeMo/NeMo
  tasks:
    - import_tasks: tasks/compfuzor.includes
