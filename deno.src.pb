---
- hosts: all
  vars:
    TYPE: deno
    INSTANCE: git
    REPO: https://github.com/denoland/deno
    BINS:
    - name: build.sh
      basedir: True
      exec: |
        cargo build --locked --release $*
        ln -sf $(pwd)/target/release/deno bin/deno
      run: True
    - name: deno
      global: True
      src: False
      delay: postRun
  tasks:
  - include: tasks/compfuzor.includes type=src
