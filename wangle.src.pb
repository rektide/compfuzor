---
- hosts: all
  vars:
    REPO: https://github.com/facebook/wangle
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('git')}}"
      fizz: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('git')}}"
    PKGS:
    - libevent-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libboost-dev
    - libdouble-conversion-dev
    - zlib1g-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
