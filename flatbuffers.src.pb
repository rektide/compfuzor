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
      content: |
        #bazel build :all
        mkdir -p release
        cd release
        cmake -G "Unix Makefiles" ..
        make
  tasks:
  - include: tasks/compfuzor.includes type=src
