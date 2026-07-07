---
# Fizz is a TLS 1.3 implementation built on folly.
# Per fizz/fizz/CMakeLists.txt the direct CONFIG deps are:
#   folly, fmt, OpenSSL, Glog, Threads, Zstd, Sodium, gflags, ZLIB, Libevent
# The README additionally names folly, OpenSSL, and libsodium as the three
# primary deps. folly is built separately (folly.src.pb) and resolved via
# CMAKE_DEPS; folly-config.cmake then re-finds its own deps via
# find_dependency, so folly's transitive system packages are listed here too.
# fmt is bundled inside folly's source but fizz calls find_package(fmt CONFIG)
# directly, so it needs fmtlib.src.pb installed and pointed at via CMAKE_DEPS.
# CMAKE_POLICY_VERSION_MINIMUM defaults to 3.10 via the cmake subsystem,
# which fizz's CMakeLists.txt requires.
- hosts: all
  vars:
    REPO: https://github.com/facebookincubator/fizz
    # fizz's CMakeLists.txt lives in fizz/fizz/, not at the repo root.
    # Without this, cmake -S . fails with "Cannot find CMakeLists.txt".
    # Mirrors the README example where the positional source arg points at
    # the dir containing CMakeLists.txt.
    CMAKE_SOURCE_DIR: fizz
    CMAKE: True
    CMAKE_INSTALL: True
    CMAKE_INSTALL_PREFIX: True
    CMAKE_DEPS:
      folly: "{{OPTS_DIR}}/folly-{{INSTANCE|default('git')}}"
      fmt: "{{OPTS_DIR}}/fmtlib-{{INSTANCE|default('git')}}"
    PKGS:
    # fizz direct deps (fizz/fizz/CMakeLists.txt find_package calls)
    - libssl-dev
    - libzstd-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - zlib1g-dev
    - libevent-dev
    - libsodium-dev
    # also needs fmtlib.src.pb (see CMAKE_DEPS above)
    # folly transitive deps: present so folly-config.cmake find_dependency succeeds
    - libdouble-conversion-dev
    - libiberty-dev
    - liblz4-dev
    - liblzma-dev
    - libsnappy-dev
    - libjemalloc-dev

  tasks:
    - import_tasks: tasks/compfuzor.includes
