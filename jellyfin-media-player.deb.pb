---
- hosts: all
  vars:
    TYPE: jellyfin-media-player
    INSTANCE: main
    GET_URLS: "{{deb}}"
    PKGS:
      - libcec6
      - libqt5webengine5
      - qml-module-qtwebengine
      - qml-module-qtwebchannel
    BINS:
      - name: install.sh
        content: "dpkg -i {{DIR}}/src/{{deb|basename}}"
        become: True
        run: True
    deb: https://github.com/jellyfin/jellyfin-media-player/releases/download/v1.9.1/jellyfin-media-player_1.9.1-1_amd64-bookworm.deb
  tasks:
    - include: tasks/compfuzor.includes type=opt
