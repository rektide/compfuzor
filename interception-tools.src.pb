---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: git
    # git-build fallback lane. Debian REMOVED interception-tools from sid
    # (2026-06-26, "package is gone" per tracker; the trixie copy survives
    # only through the debian-stable pin-100 backstop) and upstream is
    # dormant -- this lane keeps a self-built escape hatch for when the
    # trixie packages age out of the archive. Staged, not installed by
    # default: build with bin/build.sh when needed.
    REPOS:
      interception-tools: https://gitlab.com/interception/linux/tools
      caps2esc: https://gitlab.com/interception/linux/plugins/caps2esc
    PKGS:
      - build-essential
      - cmake
      - libboost-container-dev
      - libboost-dev
      - libevdev-dev
      - libudev-dev
      - libyaml-cpp-dev
    # installs into this deployment's own tree ({{DIR}}), NOT /opt and not
    # global links -- the 2020-era build shadowed /usr/bin via
    # /usr/local/bin for years; link deliberately if you build this lane
    BINS:
      - name: build-interception-tools.sh
        basedir: interception-tools
        content: |
          cmake -S . -B build -DCMAKE_INSTALL_PREFIX={{DIR}}
          cmake --build build
          cmake --install build
      - name: build-caps2esc.sh
        basedir: caps2esc
        content: |
          cmake -S . -B build -DCMAKE_INSTALL_PREFIX={{DIR}}
          cmake --build build
          cmake --install build
      - name: build.sh
        run: true
        content: |
          ./bin/build-interception-tools.sh
          ./bin/build-caps2esc.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
