---
- hosts: all
  vars:
    REPO: https://github.com/KDE/accessibility-inspector
    PKGS:
      - libqaccessibilityclient-qt6-dev
      - libkf6i18n-dev
      - libkf6coreaddons-dev
      - libkf6dbusaddons-dev
      - libkf6configwidgets-dev
      - libkf6xmlgui-dev
      - libkf6crash-dev
      - qt6-base-dev-tools
      #- 6t6-tools-dev-tools # maybe?
    CMAKE: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
