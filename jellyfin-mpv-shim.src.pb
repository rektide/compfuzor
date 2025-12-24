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
          uv venv
          uv pip install -e ".[all]"
      - name: jellyfin-mpv-shim
        basedir: repo
        global: True
        exec: |
          #source .venv/bin/activate
          uv run python run.py
          #./gen_pkg.sh
          #sudo pip3 install .
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
