---
- hosts: all
  vars:
    REPO: https://invent.kde.org/multimedia/audiotube
    CMAKE: True
    PKGS:
      - qt6-base-dev
      - qt6-declarative-dev
      - qt6-svg-dev
      - qt6-multimedia-dev
      - qt6-imageformats
      - libkf6kirigami-dev
      - libkf6i18n-dev
      - libkf6coreaddons-dev
      - libkf6crash-dev
      - libkf6windowsystem-dev
      - libkf6iconthemes-dev
      - libkf6config-dev
      - libkf6kirigamiaddons-dev
      - libpybind11-dev
      - pybind11-dev
      - python3-ytmusicapi
      - python3-yt-dlp
      - qml6-module-qtmultimedia
      - qml6-module-qtquick-controls
      - libqcoro6-dev
      - libgstreamer1.0-dev
      - libgstreamer-plugins-base1.0-dev
      - gstreamer1.0-plugins-good
      - gstreamer1.0-plugins-bad
  tasks:
    - import_tasks: tasks/compfuzor.includes
