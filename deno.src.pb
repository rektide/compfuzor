---
- hosts: all
  vars:
    TYPE: deno
    INSTANCE: git
    REPO: https://github.com/denoland/deno
    BINS:
    - name: build.sh
      exec: "cargo build"
      run: true
  tasks:
  - include: tasks/compfuzor.includes type=src