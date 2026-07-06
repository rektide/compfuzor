---
- hosts: all
  vars:
    REPO: https://github.com/facebookincubator/fizz
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('-git')}}"
    PKGS:
    - libevent-dev
    - libdouble-conversion-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libiberty-dev
    - liblz4-dev
    - liblzma-dev
    - libsnappy-dev
    - zlib1g-dev
    - libjemalloc-dev
    - libsodium-dev

  tasks:
    - import_tasks: tasks/compfuzor.includes
