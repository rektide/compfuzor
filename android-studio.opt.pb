---
- hosts: all
  vars:
    TYPE: android-studio
    INSTANCE: main
    TGZ: https://redirector.gvt1.com/edgedl/android/studio/ide-zips/3.6.3.0/android-studio-ide-192.6392135-linux.tar.gz
    BINS:
    - name: studio.sh
      global: android-studio
      exists: True
  tasks:
  - include: tasks/compfuzor.includes type=opt
