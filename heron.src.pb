- hosts: all
  vars:
    TYPE: heron
    INSTNACE: git
    REPO: https://github.com/apache/incubaing-heron
    BINS:
    - name: build.sh
      run: True
      basedir: True
      content: bazel build --config=debian heron/...
  tasks:
  - include: tasks/compfuzor.includes type=src
