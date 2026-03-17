---
- hosts: all
  vars:
    REPO: https://github.com/mhx/dwarfs
    CMAKE: True
    CMAKE_INSTALL: True
    PKGS:
      - ronn
      - librange-v3-dev
      - libboost-chrono1.83-dev
      - libboost-program-options1.83-dev
      - libboost-context1.83-dev
      - libboost-filesystem1.83-dev
      - libboost-regex1.83-dev
      - libdouble-conversion-dev
      - libgoogle-glog-dev
      - libfast-float-dev
      - libflac-dev
      - libutf8proc-dev
      - python3-mistletoe
  tasks:
    - import_tasks: tasks/compfuzor.includes
