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
      - "source `whereis virtualenvwrapper.sh | awk '{print $2}'`/virtualenvwrapper.sh"
      - "workon {{NAME}}"
      - "./GMusicProxy $*"
      global: True
    PKGS:
    - virtualenvwrapper
    - virtualenv
    - libssl-dev
    - python2.7-dev

  tasks:
  - include: tasks/compfuzor.includes type=src
