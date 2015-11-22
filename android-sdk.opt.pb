---
- hosts: all
  vars:
    TYPE: android-sdk
    INSTANCE: 24.3.4
    TGZ: http://dl.google.com/android/android-sdk_r24.3.4-linux.tgz
  tasks:
  - include: tasks/compfuzor.includes type=opt
  - command: find {{DIR}}/tools -maxdepth 1 -type f -perm -111 -print -exec ln -s {} /usr/local/bin \;
    sudo: True
