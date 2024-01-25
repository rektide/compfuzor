---
- hosts: all
  vars:
    TYPE: jellyfin-mpv-shim
    INSTANCE: git
    REPO: https://github.com/jellyfin/jellyfin-mpv-shim
    PKGS:
      - python3-mpv
      - python3-pip
      - python3-pystray
      - python3-websocket
      - python3-webview
      - python3-wheel
      - mpv
      - libmpv-dev
    BINS:
      - name: deps.sh
        exec: |
          shopt -s nullglob
          for py in /usr/lib/python3*/EXTERNALLY-MANAGED
          do
            sudo mv $py $py.fuckoff
          done
          pip3 install --upgrade jellyfin-apiclient-python python-mpv-jsonipc pypresence
      - name: build.sh
        basedir: repo
        exec: |
          ./gen_pkg.sh
          sudo pip3 install .
  tasks:
    - include: tasks/compfuzor.includes type=src
