---
# actually working copy/paste
- hosts: all
  vars:
    TYPE: oscclip
    INSTANCE: git
    REPO: https://github.com/rumpelsepp/oscclip 
    BINS:
      - name: build.sh
        run: True
        basedir: repo
        exec: poetry install
      - name: osc-copy
        basedir: repo
        global: True
        exec: poetry run osc-copy
      - name: osc-paste
        basedir: repo
        global: True
        exec: poetry run osc-paste
    PKGS:
      - python3-dbus
      - python3-poetry
      - python3-secretstorage
    ENV:
      PYTHON_KEYRING_BACKEND: keyring.backends.null.Keyring
  tasks:
    - include: tasks/compfuzor.includes type=opt
