---
- hosts: all
  vars:
    REPO: https://github.com/rsocket/rsocket-cpp
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
    CMAKE_ARGS:
      # BUILD_TESTS is off because rsocket's gmock ExternalProject_Add
      # (CMakeLists.txt:141) doesn't declare BYPRODUCTS for libgmock.a, so
      # Ninja refuses to link it ("no known rule to make it"). Make would
      # tolerate it, but the proper fix is to carry a patch adding
      # BYPRODUCTS ${GMOCK_LIBS} to the ExternalProject build step and
      # re-enable tests. We skip tests for now since this builds rsocket as
      # a library dep, not to run its suite.
      - "-DBUILD_TESTS=OFF"
      - "-DBUILD_BENCHMARKS=OFF"
      - "-DBUILD_EXAMPLES=OFF"
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('git')}}"
    PKGS:
    - libboost-all-dev
    - googletest
    - libgtest-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libgmock-dev
    - google-mock
  tasks:
    - import_tasks: tasks/compfuzor.includes
