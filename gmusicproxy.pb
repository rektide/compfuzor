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
    #- name: GMusicProxy
    #  global: gmusicproxy
    #  basedir: True
    #  src: False
    - name: gmusicproxy
      execs:
      - "cd repo"
      - "./GMusicProxy $*"
      global: True
    PKGS:
    - libssl-dev
    - python2.7-dev

  tasks:
  - include: tasks/compfuzor.includes type=opt
