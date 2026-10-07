---
- hosts: all
  vars:
    TYPE: patchance
    INSTANCE: git
    REPO: https://github.com/Houston4444/Patchance.git
    # The jj archive runner does not support submodule deployment yet.
    ARCHIVE_DOWNLOAD: false
    GIT_SUBMODULES: true
    PKGS:
      - make
      - git
      - pyqt6-dev-tools
      - qt6-base-dev-tools
      - qtchooser
      - qttools5-dev-tools
      - qt6-svg-plugins
      - python3-pyqt6
      - python3-pyqt6.qtsvg
      - python3-qtpy
      - python3-jack-client
      - python3-liblo
      - python3-pyalsa
      - fonts-roboto
    BINS:
      - name: build.sh
        basedir: repo
        run: true
        exec: |
          make QT_VERSION=6
      - name: install.sh
        basedir: repo
        exec: |
          sudo make install PREFIX=/usr/local
          # Upstream copies source directories, preserving restrictive modes.
          sudo chmod -R a+rX /usr/local/share/patchance
  tasks:
    - import_tasks: tasks/compfuzor.includes
