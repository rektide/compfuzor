- hosts: all
  vars:
    REPO: https://github.com/google/flatbuffers
    BAZEL: True
    BAZEL_TARGET: "//:flatc"
    BAZEL_INSTALL_TARGETS:
    - ":flatc"
  tasks:
    - import_tasks: tasks/compfuzor.includes type=src
