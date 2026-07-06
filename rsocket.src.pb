---
- hosts: all
  vars:
    REPO: https://github.com/rsocket/rsocket-cpp
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
    CMAKE_ARGS:
      - "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('git')}}"
    PKGS:
    - googletest
    - libgtest-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libgmock-dev
    - google-mock
  tasks:
    - import_tasks: tasks/compfuzor.includes
