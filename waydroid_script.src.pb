---
- hosts: all
  vars:
    TYPE: waydroid_script
    INSTANCE: git
    REPO: https://github.com/casualsnek/waydroid_script
    BINS:
      - name: build.sh
        exec: |
          python3 -m venv venv
          venv/bin/pip install -r requirements.txt
      - name: install.sh
        sudo: True
        exec: |
          venv/bin/python3 main.py
  tasks:
    - import_tasks: tasks/compfuzor.includes
