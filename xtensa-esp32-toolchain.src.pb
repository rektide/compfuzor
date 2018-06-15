- hosts: all
  vars:
    TYPE: xtensa-esp32-toolchain
    INSTANCE: xtensa-1.22.x
    REPO: https://github.com/espressif/esp-idf.git
    ENV:
      PATH: "{{REPO}}/builds/xtensa-esp32-elf/bin:$PATH"
    PKGS:
    - gperf
    - texinfo
    - help2man
    - python-serial
    - libpython2.7-dev
    # DEVEL pkgs
    #- bison
    #- flex
    #- ncurses
    #- make
    BINS:
    - name: build.sh
      #run: True
      basedir: "{{DIR}}/repo"
      content: |
        ./bootstrap
        ./configure --enable-local --prefix={{DIR}}
        make install
        ./ct-ng xtensa-esp32-elf
        ./ct-ng build
        chmod -R u+w builds/xtensa-esp32-elf
  tasks:
  - include: tasks/compfuzor.includes type=opt
