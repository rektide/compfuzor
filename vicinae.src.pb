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
    # Named keybinding declarations (reviewed cutover values: see
    # examples/keybindings/vicinae.yaml and
    # design/keybindings/vicinae-proposal0.gpt61sol.md). The generator
    # packages action/<id>.yaml + keybinding/<id>.yaml and synthesizes
    # user-scoped install-keybindings-{niri,umbriel}.sh installers; the
    # hand-authored KDL/TOML fragments and bespoke install-niri.sh /
    # install-umbriel.sh bodies they replace are gone.
    # NAME defaults to "vicinae-git" here (TYPE + git instance); the durable
    # membership group ID reads better as plain "vicinae":
    KEYBINDING_PRODUCER: vicinae
    KEYBINDING_ACTIONS:
      vicinae-toggle:
        exec: [vicinae, toggle]
      vicinae-clipboard:
        exec: [vicinae, deeplink, "vicinae://launch/clipboard/history"]
        umbriel:
          exec: [vicinae, deeplink, "vicinae://launch/clipboard/history?toggle=true"]
      vicinae-switch-windows:
        exec: [vicinae, deeplink, "vicinae://launch/wm/switch-windows"]
        umbriel:
          exec: [vicinae, deeplink, "vicinae://launch/wm/switch-windows?toggle=true"]
    KEYBINDINGS:
      vicinae-launch:
        action: vicinae-toggle
        keys: [Mod+D]
        title: "Run an Application: vicinae"
        umbriel:
          keys: [Mod+Space]
      vicinae-clipboard:
        action: vicinae-clipboard
        keys: [Alt+Grave]
        title: "Vicinae clipboard"
        umbriel:
          keys: [] # Umbriel's Mod+Grave chord is the consumer-owned patch in umbriel.etc.pb.
      vicinae-switch-windows:
        action: vicinae-switch-windows
        keys: [Mod+F]
        title: "Switch windows: vicinae"
        umbriel:
          keys: [Mod+Slash]
    # Shared producer targets in vars/common.yaml bind the home-local consumer
    # profiles at invocation, independently of Vicinae's source deployment and
    # service audiences. Profile environment overrides select shared material.
    # These stay USER-scoped installers joined into install-user.sh; they
    # do not become system build/install operations.
    ETC_DIRS:
      - kde/kwin-scripts/vicinae/contents/code
    ETC_FILES:
      # KDE: kwin hosts org.kde.kglobalaccel on Plasma 6, so the scriptable
      # shortcut-registration path is a kwin script (string keys, rebindable
      # in the shortcuts KCM, autostarted via kwinrc [Plugins]). KDE is not
      # part of the named-keybindings consumer world yet and keeps its
      # hand-authored resources + install-kde.sh unchanged.
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
          # The generated install-keybindings-{niri,umbriel}.sh children are
          # appended here by gen_bins: they register this producer's named
          # bindings into the common consumer hosts (niri.etc.pb / umbriel.etc.pb),
          # unless KEYBINDING_TARGETS overrides them. Run their consumer installers
          # (install.mjs) once first for root adoption. This deployment retains
          # its existing compatible install-user.sh/service behavior.
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
