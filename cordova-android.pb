---
- hosts: all
  vars:
    TYPE: cordova-android
    INSTANCE: git
    REPO: https://github.com/apache/cordova-android
    PKGS:
    - ant
    platform: 19
  tasks:
  - include: tasks/compfuzor.includes type=src
  - shell: npm install -g cordova
    sudo: True
  - shell: chdir="{{DIR}}/framework" android update project -p . -t android-{{platform}}
  - shell: chdir="{{DIR}}/framework" ant jar
  - shell: ln -s "{{DIR}}/framework/cordova*jar" "{{SRCS_DIR}}"
