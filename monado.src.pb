---
- hosts: all
  vars:
    REPO: https://gitlab.freedesktop.org/monado/monado
    CMAKE: True
    PKGS:
      - libopenhmd-dev
      - libonnxruntime-dev
      - libuvc-dev
      - libopenvr-dev
      - libopenxr-utils
      - libopenxr-loader1
      - libopenxr-dev
      #- libopenxr1-monado
      # not on debian:
      #- depthai
      #- realsense
      #- leapv2
      #- leapsdk
      #- survive
    BINS:
      - name: install.sh
        generatedAt: false
        basedir: build
        content: |
          cmake --build . --target install
      - name: install-user.sh
        content: |
          # removedriver
          ~/.steam/steam/steamapps/common/SteamVR/bin/vrpathreg.sh adddriver {{BUILD_DIR}}/steamvr-monado
          ~/.steam/steam/steamapps/common/SteamVR/bin/vrpathreg.sh 
  tasks:
    - import_tasks: tasks/compfuzor.includes
