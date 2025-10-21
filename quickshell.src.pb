---
- hosts: all
  vars:
    TYPE: quickshell
    INSTANCE: git
    REPO: https://git.outfoxxed.me/quickshell/quickshell
    BINS:
      - name: build.sh
        content: |
          # crash-reporter requires google-breakpad
          cmake -GNinja -B build -DCRASH_REPORTER=OFF
          cmake --build build
          sudo cmake --install build
    PKGS:
      - qt6-shadertools-dev
      - libcli11-dev
      - libjemalloc-dev
      - libpam0g-dev
      - libpipewire-0.3-dev
      - qml6-module-qtmultimedia
  tasks:
    - import_tasks: tasks/compfuzor.includes
