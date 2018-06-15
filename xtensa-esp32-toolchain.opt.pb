- hosts: all
  vars:
    TYPE: xtensa-esp32
    INSTANCE: 1.22.0-61
    TGZ: https://dl.espressif.com/dl/xtensa-esp32-elf-linux64-1.22.0-61-gab8375a-5.2.0.tar.gz
    ENV:
      PATH: "{{DIR}}/bin:$PATH"
    #PKGS:
    #- gperf
    #- texinfo
    #- help2man
    #- python-serial
    #- libpython2.7-dev
    ## DEVEL pkgs
    ##- bison
    ##- flex
    ##- ncurses
    ##- make
    #BINS:
    #- name: build.sh
    #  #run: True
    #  basedir: "{{DIR}}/repo"
    #  content: |
    #    ./bootstrap
    #    ./configure --enable-local --prefix={{DIR}}
    #    make install
    #    ./ct-ng xtensa-esp32-elf
    #    ./ct-ng build
    #    chmod -R u+w builds/xtensa-esp32-elf
  tasks:
  - include: tasks/compfuzor.includes type=opt
