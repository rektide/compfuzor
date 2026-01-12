---
- hosts: all
  vars:
    REPO: https://github.com/davidedmundson/kiot
    CMAKE: True
    CMAKE_ARGS: -DQT_NO_PACKAGE_VERSION_CHECK=TRUE -DQt6Mqtt_DIR=/usr/local/lib/x86_64-linux-gnu/cmake/Qt6Mqtt
    PKGS:
     - libkf6idletime-dev
     - libkf6solid-dev
     - libkf6kcmutils-dev
     - libkf6bluezqt-dev
     - libkf6pulseaudioqt-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
