---
- hosts: all
  vars:
    TYPE: deno
    INSTANCE: main
    GET_URLS:
      - url: https://deno.land/x/install/install.sh
        dest: deno-install.sh
    BINS:
      - name: install.sh
        basedir: src
        run: True
        content: |
          DENO_INSTALL=$DIR sh deno-install.sh $*
          ln -sf $DIR/bin/deno ${GLOBAL_BINS_DIR}/deno
    ENV:
      GLOBAL_BINS_DIR: "{{GLOBAL_BINS_DIR}}"
  tasks:
    - include: tasks/compfuzor.includes type=opt
