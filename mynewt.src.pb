---
- hosts: all
  vars:
    TYPE: mynewt
    INSTANCE: git
    REPOS:
    - https://github.com/apache/incubator-mynewt-core
    - https://github.com/apache/incubator-mynewt-newt
    - https://github.com/apache/incubator-mynewt-newtmgr
    - https://github.com/apache/incubator-mynewt-blinky
    - https://github.com/apache/incubator-mynewt-documentation
    - https://github.com/apache/incubator-mynewt-newt
    BINS:
    - name: build.sh
      execs:
      - cd repo/incubator-mynewt-newt
      - ./build.sh
      run: True
    - name: newt
      basedir: "{{DIR}}/repo/incubator-mynewt-newt/newt"
      src: False
      global: True
  tasks:
  - include: tasks/compfuzor.includes
