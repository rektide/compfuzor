---
- hosts: all
  vars:
    TYPE: gmusicmpd
    INSTANCE: git
    REPO: https://github.com/Illyism/GMusic-MPD
    BINS:
    - exec: npm install
    - name: gmusic-mpd.js
      global: gmusicmpd
      basedir: True
      src: False
  tasks:
  - include: tasks/compfuzor.includes type=src
