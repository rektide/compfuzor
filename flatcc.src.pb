- hosts: all
  vars:
    TYPE: flatcc
    INSTANCE: git
    REPO: https://github.com/dvidelabs/flatcc
    BINS:
    - name: build.sh
      basedir: True
      run: True
      contents: |
        mkdir -p release
        cd release
        cmake ..
        make
    - name: flatcc
      global: True
  tasks:
  - include: tasks/compfuzor.includes type=src
