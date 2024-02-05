---
- hosts: all
  vars:
    TYPE: jellyfin-mpv-shim
    INSTANCE: main
    SYSTEMD_ENABLE: False
    ENV: True
    VAR_FILES:
      - name: jellyfin-mpv-shim.desktop
        contents: |
          [Desktop Entry]
          Name=Jellyfin MPV Shim
          Comment=Jellyfin MPV Shim
          Exec=jellyfin-mpv-shim
          #Icon=steam_icon_1944570
          Terminal=false
          Type=Application
          Categories=AudioVideo;
    BINS:
      - name: install.sh
        exec: |
          #systemctl --user enable $NAME
          ln -s $(pwd)/var/jellyfin-mpv-shim ~/.local/share/applications/
          ln -s $(pwd)/var/jellyfin-mpv-shim ~/.config/autostart/
  tasks:
    - include: tasks/compfuzor.includes type=srv
