---
- hosts: all
  vars:
    TYPE: android-studio
    INSTANCE: main
    TGZ: https://redirector.gvt1.com/edgedl/android/studio/ide-zips/4.0.0.16/android-studio-ide-193.6514223-linux.tar.gz
    BINS:
    - name: studio.sh
      global: android-studio
      exists: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
