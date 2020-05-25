---
- hosts: all
  vars:
    TYPE: redshift
    INSTANCE: wlr
    # this is a fork, which has wayland support
    REPO: https://github.com/minus7/redshift
    PKGS:
    - libwlroots-dev
    - libxrandr-dev
    # huge and doesn't seem to make a difference, was enabled even without?
    #- libgeoclue-dev
    OPT_DIR: True
    BINS:
    - name: build.sh
      exec: |
        ./bootstrap && \
        ./configure --prefix={{OPT}} && \
        make && \
        make install
  tasks:
  - include: tasks/compfuzor.includes type=src
