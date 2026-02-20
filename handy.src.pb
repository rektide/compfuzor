---
- hosts: all
  vars:
    REPO: https://github.com/cjpais/Handy
    TOOL_VERSIONS:
      bun: True
      rust: True
    PKGS:
      - build-essential
      - libasound2-dev
      - pkg-config
      - libssl-dev
      - libvulkan-dev
      - vulkan-tools
      - glslc
      - libgtk-3-dev
      - libwebkit2gtk-4.1-dev
      - libayatana-appindicator3-dev
      - librsvg2-dev
      - patchelf
      - cmake
      - wtype
      - ydotool
      # tauri
      - libxdo-dev
    ENV:
      model: whisper-large
    ETC_DIRS:
      - niri
    ETC_FILES:
      - name: niri/handy.kdl
        content: |
          binds {
            Mod+G hotkey-overlay-title="Toggle transcription: Handy" { spawn-sh "handy --toggle-transcription"; }
          }
    SHARE_FILES:
      - name: parakeet.tar.gz.url
        content: https://blob.handy.computer/parakeet-v3-int8.tar.gz
      - name: whisper-large.bin.url
        content: https://blob.handy.computer/ggml-large-v3-q5_0.bin
      - name: whisper-turbo.bin.url
        content: https://blob.handy.computer/ggml-large-v3-turbo.bin
      - name: whisper-medium.bin.url
        content: https://blob.handy.computer/whisper-medium-q4_1.bin
    BINS:
      - name: install-user.sh
        content: |
          mkdir -p ~/.config/com.pais.handy/models
      - name: build.sh
        content: |
          bun install

          [ -n "$TAURI_SIGNING_PRIVATE_KEY" ] || TAURI_SIGNING_PRIVATE_KEY=$HOME/.config/tauri/{{NAME}}.key
          if [ ! -e "$TAURI_SIGNING_PRIVATE_KEY" ]
          then
            mkdir -p $(dirname "$TAURI_SIGNING_PRIVATE_KEY")
            npm run tauri signer generate -- -w $TAURI_SIGNING_PRIVATE_KEY
          fi

          #bun run build
          bun run tauri build --no-bundle
      - name: install.sh
        content: |
          ln -sfv $(pwd)/src-tauri/target/release/handy $GLOBAL_BINS_DIR
      - name: install-niri.sh
        content: |
          NIRI_CONFIG=~/.config/niri/config.kdl
          mkdir -p ~/.config/niri/handy
          for f in {{DIR}}/etc/niri/*.kdl; do
            ln -sf "$f" ~/.config/niri/handy/
            echo 'include "./handy/'"$(basename "$f")"'"'
          done | block-in-file -n handy --comment "//" "$NIRI_CONFIG"
  tasks:
    - import_tasks: tasks/compfuzor.includes
