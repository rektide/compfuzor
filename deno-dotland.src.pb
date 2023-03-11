---
- hosts: all
  vars:
    TYPE: deno-dotland
    INSTANCE: git
    REPO: https://github.com/denoland/dotland
    BINS:
      - name: run.sh
        basedir: repo
        exec: deno task start
  tasks:
    - include: tasks/compfuzor.includes type=opt
