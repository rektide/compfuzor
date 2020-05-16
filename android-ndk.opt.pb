---
- hosts: all
  vars:
    TYPE: android-ndk
    INSTANCE: main
    PKGSSET: ANDROID
    ETC_DIR: True
    #ETC_FILES:
    #- name: pkgs
    #  exec: |
    #    {{PKGS_ALL()}}
  tasks:
  - include: tasks/compfuzor.includes
