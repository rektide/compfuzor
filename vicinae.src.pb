---
- hosts: all
  vars:
    TYPE: vicinae
    INSTANCE: git
    REPO: https://github.com/vicinaehq/vicinae
    TOOL_VERSIONS:
      nodejs: True
    PKGS:
      - build-essential
      - cmake
      - ninja-build
      - qt6-base-dev
      - qt6-svg-dev
      - qt6-wayland-dev
      - libqt6svg6
      - libprotobuf-dev 
      - cmark-gfm
      - libcmark-gfm-dev
      - libcmark-gfm-extensions-dev
      - layer-shell-qt
      - liblayershellqtinterface-dev
      - libqalculate-dev
      - libminizip-dev
      - libabsl-dev
      - zlib1g-dev
      - qtkeychain-qt6-dev
      - librapidfuzz-cpp-dev
      - libglaze-dev
      - libqalculate-dev
    DIRS:
      - "/usr/share/vicinae/extra"
    #LINKS:
    #  "/usr/share/vicinae/extra/themes": "extra/themes"
    #  "/usr/share/applications/vicinae.desktop": "extra/vicinae.desktop"
    #  "/usr/share/applications/vicinae-url-handler.desktop": "extra/vicinae-url-handler.desktop"
    #  "/usr/lib/systemd/user/vicinae.service": "extra/vicinae.service"
    #  "/usr/share/icons/hicolor/scalable/apps/vicinae.svg": "vicinae/icons/vicinae.svg"
    #  "/etc/chromium/native-messaging-hosts/com.vicinae.vicinae.json": "build/src/browser-extension/com.vicinae.vicinae.chromium.json"
    ENV: True
    ETC_DIRS:
      - niri
    ETC_FILES:
      - name: niri/keybinding-launch.kdl
        content: |
          binds {
            Mod+D hotkey-overlay-title="Run an Application: vicinae" { spawn-sh "vicinae toggle"; }
          }
      - name: niri/keybinding-clipboard.kdl
        content: |
          binds {
            Alt+Grave hotkey-overlay-title="Vicinae clipboard" { spawn-sh "vicinae vicinae://extensions/vicinae/clipboard/history"; }
          }
      - name: niri/keybinding-switch-windows.kdl
        content: |
          binds {
            Mod+F hotkey-overlay-title="Switch windows: vicinae" { spawn-sh "vicinae vicinae://extensions/vicinae/wm/switch-windows"; }
          }
    BINS:
      - name: build.sh
        content: |
          mkdir -p build
          #cmake -G Ninja .. \
          #  -DLTO=ON
          #  -DCMAKE_BUILD_TYPE=Release \
          #  -DVICINAE_PROVENANCE=compfuzor \
          #  -B build
          #cmake --build build
          #make release
          make host-optimized
      - name: install.sh
        content: |
          #ln -s $(pwd)/build/vicinae/vicinae $GLOBAL_BINS_DIR/
          cmake --install build
          sudo systemctl daemon-reload
      - name: install-user.sh
        content: |
          systemctl --user enable vicinae.service
      - name: install-niri.sh
        basedir: etc
        content: |
          NIRI_CONFIG_DIR="$HOME/.config/niri"
          mkdir -p "$NIRI_CONFIG_DIR/vicinae"
          for f in {{DIR}}/etc/niri/*.kdl; do
            ln -sf "$f" $NIRI_CONFIG_DIR/vicinae
            echo 'include "./vicinae/'"$(basename "$f")"'"'
          done | block-in-file -n vicinae --comment "//" "$NIRI_CONFIG_DIR/config.kdl
  tasks:
    - import_tasks: tasks/compfuzor.includes
