---
- hosts: all
  gather_facts: False
  vars:
    TYPE: rtorrent
    INSTANCE: main
    USERMODE: True

    DIRS:
    - "{{incomplete}}"
    - "{{complete}}"
    ETC_FILES:
    - rtorrent.rc
    VAR_DIRS:
    - session
    PKGS:
    - rtorrent

    LINKS:
      "~/.rtorrent.rc": "{{ETC}}/rtorrent.rc"
      "~/.torrent": "{{VAR}}"

    complete: "{{XDG.XDG_DOWNLOAD_DIR}}/torrent"
    incomplete: "{{XDG.XDG_DOWNLOAD_DIR}}/torrent/_incomplete"
  tasks:
  - include: tasks/compfuzor.includes
  - file: path={{complete}} state=directory
  - file: path={{incomplete}} state=directory
