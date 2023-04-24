---
- hosts: all
  vars:
    TYPE: block-in-file
    INSTANCE: git
    REPO: https://github.com/jauntywunderkind/block-in-file
    BINS:
      - name: install.sh
        basedir: repo
        content: |
          # deno automatically adds "/bin" to the path so pre-remove our copy of it
          ROOT=$(dirname $GLOBAL_BINS_DIR) deno task install:dir
    ENV:
      GLOBAL_BINS_DIR: "{{GLOBAL_BINS_DIR}}"
  tasks:
    - include: tasks/compfuzor.includes type=opt
