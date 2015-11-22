---
- hosts: all
  vars:
    TYPE: openhip
    INSTANCE: svn
    SVN_REPO: http://svn.code.sf.net/p/openhip/code/hip
    OPT_DIR: True
    PKGS:
    - libxml2-dev
    BINS:
    - exec: ./bootstrap.sh
    - exec: "./configure --prefix={{DIR}}"
    - exec: make
    - exec: make install
  tasks:
  - include: tasks/compfuzor.includes type=src
