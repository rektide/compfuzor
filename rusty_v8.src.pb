---
- hosts: all
  vars:
    TYPE: rusty_v8
    #INSTANCE: main
    INSTANCE: android
    #REPO: https://github.com/denoland/rusty_v8
    REPO: https://github.com/gponsinet/rusty_v8
    #GIT_VERSION:
    GIT_VERSION: android-support
    BINS:
    - name: build.sh
      exec: "cargo build"
      run: true
 tasks:
  - include: tasks/compfuzor.includes type=src
