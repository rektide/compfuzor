---
- hosts: all
  vars:
    TYPE: moonlight
    INSTANCE: git
    REPO: https://github.com/moonlight-stream/moonlight-qt
    BINS:
      - name: build.sh
        exec: |
          qmake6 moonlight-qt.pro
          make
      - name: install.sh
        become: True
        exec: |
          make install
    PKGS:
      - libegl1-mesa-dev
      - libgl1-mesa-dev
      - libopus-dev
      - libsdl2-dev
      - libsdl2-ttf-dev
      - libssl-dev
      - libavcodec-dev
      - libavformat-dev
      - libva-dev
      - libvdpau-dev
      - libxkbcommon-dev 
      - wayland-protocols
      - libdrm-dev
      - qt6-base-dev
      - qt6-declarative-dev
      - qt6-svg-dev
      - qt6-tools-dev
      - qml6-module-qtqml-workerscript
      - qml6-module-qtquick
      - qml6-module-qtquick-controls
      - qml6-module-qtquick-layouts
      - qml6-module-qtquick-templates
      - qml6-module-qtquick-window
      - libplacebo-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
