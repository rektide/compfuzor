# unified-remote server
---
- hosts: all
  vars:
    TYPE: urserver 
    INSTANCE: main
    version: 3.8.0.2451
    rev: "{{ version[-4:] }}"
    arch: linux-x64
    prefix: "https://www.unifiedremote.com/static/builds/server/linux-x64/{{rev}}"
    DEB: "{{prefix}}/urserver-{{version}}.deb"
    TGZ: "{{prefix}}/urserver-{{version}}.tar.gz"

    BIN_DIRS: True
    BINS:
    - name: urserver
      link: "{{DIR}}/urserver"
      global: True
    SYSTEMD_EXEC: "{{BIN}}/urserver"
  tasks:
  - include: tasks/compfuzor.includes type=opt
