---
- hosts: all
  vars:
    TYPE: arangodb
    INSTANCE: git
    REPO: https://github.com/arangodb/arangodb
    PKGS:
    - libssl-dev
    - libjemalloc-dev
    - cmake
    - build-essential
    - flex
    - bison
    BINS:
    - name: build.sh
      exec: |
        git submodule update --recursive
        git submodule update --init --recursive
        mkdir build
        cd build
        cmake ..
  tasks:
  - include: tasks/compfuzor.includes type=src
