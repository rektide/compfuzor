- hosts: all
  vars:
    TYPE: disni
    INSTANCE: git
    REPO: https://github.com/zrlio/disni
    BINS:
    - name: build.sh
      exec: |
        cd libdisni
        ./autoprepare.sh
        ./configure
        make
        cd ..
        mvn install
  tasks:
  - include: tasks/compfuzor.includes type=src
