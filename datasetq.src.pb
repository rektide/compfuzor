---
- hosts: all
  vars:
    REPO: https://github.com/datasetq/datasetq
    BINS:
      - name: install.sh
        content: cargo install --locked --path dsq-cli 
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
