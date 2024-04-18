---
- hosts: all
  vars:
    TYPE: jellyfin-mpv-shim
    INSTANCE: main
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
    ETC:
      - name: conf.json
        content: |
          vo=gpu-next
    LINKS:
      - src: "{{DIR}}/etc/conf.json"
        dest: ~/.config/jellyfin-mpv-shim/conf.json
    BINS:
      - name: install.sh
        exec: |
          #systemctl --user enable $NAME
          mkdir -p ~/.local/share/application
          ln -s $(pwd)/var/jellyfin-mpv-shim.desktop ~/.local/share/applications/
          mkdir -p ~/.config/autostart
          ln -s ~/.local/share/applications/jellyfin-mpv-shim.desktop ~/.config/autostart/
  tasks:
    - include: tasks/compfuzor.includes type=srv
