---
- hosts: all
  vars:
    REPO: https://github.com/mkiol/dsnote
    PKGS:
      - qttools5-dev
      - qtdeclarative5-dev
      - qtquickcontrols2-5-dev
      - libqt5x11extras5-dev
      - libtensorflow-lite-dev
    BINS:
      - name: build.sh
        content: |
          mkdir -p build
          cmake . -B build \
            -DCMAKE_BUILD_TYPE=Release \
            -DWITH_DESKTOP=ON
            -DBUILD_WL_CLIPBOARD=ON
  tasks:
    - import_tasks: tasks/compfuzor.includes
