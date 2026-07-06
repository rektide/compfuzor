---
- hosts: all
  vars:
    REPO: https://github.com/facebook/watchman
    CMAKE: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('-git')}}"
      fizz: "{{OPTS_DIR}}/fizz-{{INSTANCE|default('-git')}}"
      fbthrift: "{{OPTS_DIR}}/fbthrift-{{INSTANCE|default('-git')}}"
      rsocket: "{{OPTS_DIR}}/rsocket-{{INSTANCE|default('-git')}}"
      wangle: "{{OPTS_DIR}}/wangle-{{INSTANCE|default('-git')}}"
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
