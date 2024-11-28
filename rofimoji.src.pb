---
- hosts: all
  vars:
    TYPE: rofimoji
    INSTANCE: git
    REPO: https://github.com/fdw/rofimoji
    PKGS:
      - python3-poetry
    BINS:
      - name: build.sh
        exec: |
          PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring poetry install
      - name: rofimoji
        basedir: True
        exec: |
          poetry run rofimoji
  tasks:
    - import_tasks: tasks/compfuzor.includes
