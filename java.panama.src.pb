---
- hosts: all
  gather_facts: False
  vars:
    TYPE: panama
    INSTANCE: git
    HG_REPO: http://hg.openjdk.java.net/panama/panama/
    HG_RAW: True
    PKGS:
    - libx11-dev
    - libxext-dev
    - libxrender-dev
    - libxtst-dev
    - libxt-dev
    - libcups2-dev
    - libasound2-dev
    BINS:
    - exec: "bash ./get_source.sh"
    - exec: "bash ./configure"
    - exec: "make all"
  tasks:
  - include: tasks/compfuzor.includes type=src
