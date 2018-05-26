---
- hosts: all
  vars:
    TYPE: protobufs
    INSTANCE: git
    REPO: https://github.com/google/protobuf
    BINS:
    - name: build.sh
      basedir: protobuf
      content: |
        ./autogen.sh
        ./configure --prefix=/opt/protobuf
        make
        make check
        sudo make install
        sudo ldconfig
  tasks:
  - include: tasks/compfuzor.includes type=src
