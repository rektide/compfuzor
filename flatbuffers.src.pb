- hosts: all
  vars:
    TYPE: flatbuffers
    INSTANCE: git
    REPO: https://github.com/google/flatbuffers
    PKGS:
    - bazel
    BINS:
    - name: build.sh
      run: True
      basedir: True
      content: bazel build :all
  tasks:
  - include: tasks/compfuzor.includes type=src
