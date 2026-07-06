---
- hosts: all
  vars:
    REPO: https://github.com/facebook/fbthrift
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly"
      fizz: "{{OPTS_DIR}}/fizz"
      rsocket: "{{OPTS_DIR}}/rsocket"
      wangle: "{{OPTS_DIR}}/wangle"
      yarpl: "{{OPTS_DIR}}/yarpl"
    PKGS:
    - flex
    - bison
    - libboost-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libmstch-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
