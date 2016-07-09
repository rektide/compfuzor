---
- hosts: all
  gather_facts: False
  vars:
    TYPE: j2cli
    INSTANCE: git
    REPO: https://github.com/kolypto/j2cli
    VAR_DIRS:
    - venv
    PKGS:
    - python-yaml
    - python-jinja2
    - python-setuptools
    - python-wheel
    - pandoc
    BINS:
    - name: build
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
