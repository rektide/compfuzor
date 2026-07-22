---
- hosts: all
  vars:
    TYPE: solstone-tmux
    INSTANCE: git
    REPO: https://github.com/solpbc/solstone-tmux.git
    PYTHON: True
    BINS:
      - name: build.sh
        content: |
          make install
      - name: install-service.sh
        exec: |
          .venv/bin/solstone-tmux install-service
      - name: solstone-tmux
        global: True
        exec: |
          .venv/bin/solstone-tmux $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
