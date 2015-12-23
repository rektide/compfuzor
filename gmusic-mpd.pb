---
- hosts: all
  vars:
    TYPE: gmusic-mpd
    INSTANCE: git
    REPO: https://github.com/Illyism/GMusic-MPD
    BINS:
    - exec: npm install
    - name: gmusic-mpd.js
      global: gmusic-mpd
      basedir: True
      src: False
  tasks:
  - include: tasks/compfuzor.includes type=src
