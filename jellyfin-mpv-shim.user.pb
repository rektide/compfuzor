---
- hosts: all
  vars:
    TYPE: jellyfin-mpv-shim
    INSTANCE: main
    #USERMODE: True
    SYSTEMD_ENABLE: False
    ENV: True
    VAR_FILES:
      - name: jellyfin-mpv-shim.desktop
        content: |
          [Desktop Entry]
          Name=Jellyfin MPV Shim
          Comment=Jellyfin MPV Shim
          Exec=jellyfin-mpv-shim
          #Icon=steam_icon_1944570
          Terminal=false
          Type=Application
          Categories=AudioVideo;
    ETC_FILES:
      - name: mpv.conf
        content: |
          #vo=dmabuf-wayland
          vo=gpu-next
          hwdec=auto-safe
          hwdec=vulkan
          drm-vrr-enabled=yes
          spirv-compiler=auto
          tone-mapping=auto
          hdr-compute-peak=yes
          tone-mapping-mode=auto
          # https://github.com/Zamundaaa/VK_hdr_layer
          #vo=gpu-next
          gpu-api=vulkan
          gpu-context=waylandvk
          target-colorspace-hint=yes
    #LINKS:
    #  - src: "{{DIR}}/etc/mpv.conf"
    #    dest: ~/.config/jellyfin-mpv-shim/mpv.conf
    BINS:
      - name: install-systemd.sh
        exec: |
          systemctl --user enable $NAME
      - name: install-desktop.sh
        exec: |
          mkdir -p ~/.local/share/application
          ln -s $(pwd)/var/jellyfin-mpv-shim.desktop ~/.local/share/applications/
          mkdir -p ~/.config/autostart
          ln -s ~/.local/share/applications/jellyfin-mpv-shim.desktop ~/.config/autostart/
          mkdir -p ~/.config/jellyfin-mpv-shim
          ln -s $(pwd)/etc/mpv.conf ~/.config/jellyfin-mpv-shim/mpv.conf
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
