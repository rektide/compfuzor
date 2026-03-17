- hosts: all
  vars:
    REPO: https://github.com/tracel-ai/burn
  tasks:
    - import_tasks: tasks/compfuzor.includes
