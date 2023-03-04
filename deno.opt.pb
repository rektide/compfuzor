---
- hosts: all
  vars:
    TYPE: deno
    INSTANCE: main
    GET_URLS:
      - url: https://deno.land/x/install/install.sh
        dest: deno-install.sh
    BINS:
      - name: build.sh
        basedir: src
        exec: |
          sh deno-install.sh $*
  tasks:
    - include: tasks/compfuzor.includes type=opt
