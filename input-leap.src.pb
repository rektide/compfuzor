---
- hosts: all
  vars:
    TYPE: input-leap
    INSTANCE: git
    REPO: https://github.com/input-leap/input-leap
    DIRS:
     - build
    BINS:
      - name: build.sh
        basedir: build
        run: True
        exec:
          cmake -DCMAKE_INSTALL_PREFIX={{OPT}} {{REPO_DIR}}
          make
          make install
    PKGS:
      # warning: installs & starts avahi-dnsconfd!! ew!
      - libavahi-compat-libdnssd1
      - libavahi-compat-libdnssd-dev
      - qttools5-dev
      - qttools5-dev-tools
    qt_windows: https://download.qt.io/archive/qt/5.13/5.13.2/qt-opensource-windows-x86-5.13.2.exe
  tasks:
    - include: tasks/compfuzor.includes type=opt
