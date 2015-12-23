---
- hosts: all
  vars:
    TYPE: mopidy
    INSTANCE: main
    ETC_FILES:
    - mopidy.conf
    CACHE_DIR: True
    LOG_DIR: True
    VAR_DIRS:
    - local
    DIRS:
    - "{{media}}"
    - "{{playlists}}"
    LINKS:
    - "~/.config/mopidy": "{{ETC}}"
    SYSTEMD_EXEC: "/usr/bin/mopidy"
    #PKGSET: mopidy
    media: "{{XDG_MUSIC_DIR}}"
    playlists: "{{VAR}}/playlists"
  vars_files:
  - vars/xdg.vars
  tasks:
  - include: tasks/compfuzor.includes type=srv
