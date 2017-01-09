---
- hosts: all
  vars:
    TYPE: gmusicproxy
    INSTANCE: git
    REPO: https://github.com/diraimondo/gmusicproxy.git
    BINS:
    - name: build.sh
      run: True
      sudo: True
      basedir: repo
      exec: "pip install --install-option='--prefix=~/.local' -r requirements.txt"
    - name: GMusicProxy
      global: gmusicproxy
      basedir: True
      src: False
    #- name: gmusicproxy
    #  basedir: True
    #  execs:
    #  - "cd repo"
    #  - "./GMusicProxy $*"
    #  global: True
    PKGS:
    - libssl-dev
    - python2.7-dev
    - python-mutagen

  tasks:
  - include: tasks/compfuzor.includes type=src
