---
- hosts: all
  vars:
    TYPE: gmusicproxy
    INSTANCE: git
    REPO: https://github.com/diraimondo/gmusicproxy.git
    BINS:
    - name: build
      run: True
      sudo: True
    - name: GMusicProxy
      global: gmusicproxy
      basedir: True
      src: False
    PKGS:
    - virtualenvwrapper
    PKGS_BYPASS: True

  tasks:
  - include: tasks/compfuzor.includes type=src
