---
- hosts: all
  vars:
    TYPE: deno-ddoc
    INSTANCE: git
    REPO: https://github.com/denosaurs/ddoc
    BINS:
      - name: build.sh
        basedir: repo
        exec: deno run -A scripts/build.ts
      - name: run.sh
        basedir: repo
        exec: deno run -A --unstable ddoc.ts
  tasks:
    - include: tasks/compfuzor.includes type=opt
