---
- hosts: all
  vars:
    TYPE: vicinae
    INSTANCE: git
    # Canonical jj archive at ~/archive/vicinaehq/vicinae backs this
    # deployment; repo_jj_archive.tasks keeps a dedicated colocated jj/Git
    # workspace at DIR/repo (a repo symlink pointing straight at the archive
    # is admitted by the deploy runner and replaced with that workspace).
    # Evacuated local work lives under evac/* bookmarks in the archive.
    REPO: https://github.com/vicinaehq/vicinae
    GIT_VERSION: main
    TOOL_VERSIONS:
      nodejs: True
    # Matches upstream's Arch CI image (scripts/runners/arch/base.Dockerfile).
    ARCH_PKGS:
      - base-devel
      - catch2
      - ccache
      - clang
      - cmake
      - curl
      - extra-cmake-modules
      - gcc
      - git
      - jq
      - layer-shell-qt
      - libqalculate
      - mold
      - ninja
      - nodejs
      - npm
      - qt6-base
      - qt6-declarative
      - qt6-shadertools
      - qt6-svg
      - qt6-tools
      - qtkeychain-qt6
      - syntax-highlighting
      - wayland-protocols
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
      - kde/kwin-scripts/vicinae/contents/code
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
      # KDE: kwin hosts org.kde.kglobalaccel on Plasma 6, so the scriptable
      # shortcut-registration path is a kwin script (string keys, rebindable
      # in the shortcuts KCM, autostarted via kwinrc [Plugins]).
      - name: kde/kwin-scripts/vicinae/metadata.desktop
        content: |
          [Desktop Entry]
          Name=Vicinae Shortcuts
          Comment=Global shortcuts for the Vicinae launcher
          Type=Service
          X-KDE-ServiceTypes=KWin/Script
          X-KDE-PluginInfo-Name=vicinae
          X-KDE-PluginInfo-Version=1.0
          X-KDE-PluginInfo-License=GPL-3.0
      - name: kde/kwin-scripts/vicinae/contents/code/main.js
        content: |
          // KWin-owned global shortcuts for Vicinae. Keys are defaults:
          // rebind in System Settings > Shortcuts (search "Vicinae").
          registerShortcut(
            "VicinaeToggle", "Vicinae: Toggle Launcher", "Alt+Space",
            () => spawn("vicinae", "toggle"));
          registerShortcut(
            "VicinaeClipboard", "Vicinae: Clipboard History", "Alt+Grave",
            () => spawn("vicinae", "vicinae://launch/clipboard/history"));
          registerShortcut(
            "VicinaeSwitchWindows", "Vicinae: Switch Windows", "Meta+F",
            () => spawn("vicinae", "vicinae://extensions/vicinae/wm/switch-windows"));
    BINS:
      - name: build.sh
        content: |
          cd "{{DIR}}/repo"
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
          cd "{{DIR}}/repo"
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
          done | block-in-file -n vicinae --comment "//" "$NIRI_CONFIG_DIR/config.kdl"
      - name: install-kde.sh
        basedir: etc
        content: |
          DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
          SCRIPTS="$DATA/kwin/scripts"
          mkdir -p "$SCRIPTS"
          ln -sfn "{{DIR}}/etc/kde/kwin-scripts/vicinae" "$SCRIPTS/vicinae"
          # autostart at login (kwin reads [Plugins] itself; additive + idempotent)
          block-in-file -n vicinae-kwin-script --comment "#" "$HOME/.config/kwinrc" <<'EOF'
          [Plugins]
          vicinae=Enabled
          EOF
          # load into the running session without restarting kwin; the
          # [Plugins] entry carries it from the next login onward.
          # NOTE: registerShortcut defaults silently LOSE to existing key
          # owners (krunner holds Alt+Space, kwin holds Alt+`). Claiming
          # via the org.kde.KGlobalAccel D-Bus is NOT safe from scripts --
          # setForeignShortcutKeys with hand-encoded keys knocked plasmashell
          # over once (2026-09-30). Bind final keys in System Settings ->
          # Shortcuts (search "Vicinae") instead; the KCM steals cleanly.
          if busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$SCRIPTS/vicinae/contents/code/main.js" vicinae >/dev/null 2>&1; then
            busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting start >/dev/null 2>&1 \
              && echo "kwin script loaded; verify key binds in System Settings > Shortcuts (search Vicinae)" \
              || echo "kwin script registered; starts next login"
          else
            echo "no kwin on the bus; script installs for next login"
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
