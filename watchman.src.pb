---
- hosts: all
  vars:
    REPO: https://github.com/facebook/watchman
    CMAKE: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly"
      fizz: "{{OPTS_DIR}}/fizz"
      fbthrift: "{{OPTS_DIR}}/fbthrift"
      rsocket: "{{OPTS_DIR}}/rsocket"
      wangle: "{{OPTS_DIR}}/wangle"
    PKGS:
    - libelf-dev
    - libevent-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libboost-dev
    - liblz4-dev
    - libsnappy-dev
    - libdwarf-dev
    - libiberty-dev
    - libaio-dev
    - libzstd-dev
    - libdouble-conversion-dev
    - zlib1g-dev
    - liblzma-dev
    - libboost-context-dev
    - libboost-chrono-dev
    - libpcre2-dev
    - inotify-tools
  tasks:
    - import_tasks: tasks/compfuzor.includes
