---
- hosts: all
  vars:
    TYPE: solstone-linux
    INSTANCE: git
    REPO: https://github.com/solpbc/solstone-linux.git
    RUST: True
    BINS:
      - name: build.sh
        content: |
          make install
      - name: install-service.sh
        exec: |
          ~/.cargo/bin/solstone-linux install-service
  tasks:
    - import_tasks: tasks/compfuzor.includes
