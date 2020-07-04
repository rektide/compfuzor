---
- hosts: all
  vars:
    TYPE: android-sdk
    INSTANCE: main
    ZIP: https://dl.google.com/android/repository/commandlinetools-linux-6200805_latest.zip
  tasks:
  - include: tasks/compfuzor.includes type=opt
  #- command: find {{DIR}}/tools -maxdepth 1 -type f -perm -111 -print -exec ln -s {} /usr/local/bin \;
  #  sudo: True
