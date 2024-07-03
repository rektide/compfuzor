---
- hosts: all
  vars:
    TYPE: vk-hdr-layer
    INSTANCE: git
    REPO: https://github.com/Zamundaaa/VK_hdr_layer
    PKGS:
      - vkroots-headers
    BINS:
      - name: build.sh
        exec: |
          time meson setup build ${FLAGS}
          time ninja -C build
      - name: gamescope.sh
        exec: |
          gamescope --hdr-enabled --hdr-debug-force-output --steam -- env ENABLE_GAMESCOPE_WSI=1 DXVK_HDR=1 DISABLE_HDR_WSI=1 steam -bigpicture
      - name: reg.sh
        exec: |
          wine reg.exe add HKCU\\Software\\Wine\\Drivers /v Graphics /d x11,wayland $*
          # also run wine instance with DISPLAY unset
      - name: mpv.sh
        exec: |
          # attempting in jellyfin-mpv-shim.user.pb as well
          mpv --vo=gpu-next --target-colorspace-hint --gpu-api=vulkan --gpu-context=waylandvk $*
    ENV:
      DISABLE_HDR_WSI: 1
      # for Quake II RTX in Wayland native mode
      ENABLE_HDR_WSI: ""
      ENABLE_GAMESCOPE_WSI: 1
      # unset for wine
      #DISPLAY: ""
      DXVK_HDR: 1
      # also consider ENABLE_HDR_WSI
      SDL_VIDEODRIVER: wayland
      # VK_LOADER_DEBUG: error,warn,info
      VK_LOADER_DEBUG: error,warn,info
      FLAGS: ""
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
